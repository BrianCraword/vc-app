import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:forumcopilot_sdk/forumcopilot_sdk.dart';
import 'package:discourse_core/discourse_core.dart';

import '../config/app_forum_config.dart';

/// How a web view reaches a forum page as the member who is signed into the
/// app.
///
/// A web view is a different client from the app: it carries neither the
/// User API Key nor a session cookie, so it would open the forum's own pages
/// — matchmaking, the Feed's views, the research library, anything a theme
/// component draws — signed out. This works out which URL to open first, and
/// whether the view has to carry on somewhere afterwards.
///
/// The decision is kept out of the widget deliberately: a widget wrapping a
/// platform web view cannot be exercised in a unit test, and this is the part
/// worth testing.
@immutable
class ForumWebStart {
  const ForumWebStart({
    required this.url,
    required this.target,
    required this.viaConfirmation,
  });

  /// What the web view loads first.
  final Uri url;

  /// The page the member actually asked for. Equal to [url] unless
  /// [viaConfirmation].
  final Uri target;

  /// True when [url] is Discourse's one-time-password confirmation page
  /// rather than [target]. The member taps confirm there, Discourse
  /// establishes the session and redirects to the forum root, and only then
  /// does the view go on to [target].
  final bool viaConfirmation;

  @override
  bool operator ==(Object other) =>
      other is ForumWebStart &&
      other.url == url &&
      other.target == target &&
      other.viaConfirmation == viaConfirmation;

  @override
  int get hashCode => Object.hash(url, target, viaConfirmation);

  @override
  String toString() => 'ForumWebStart($url -> $target, '
      'viaConfirmation: $viaConfirmation)';
}

class ForumWebEntry {
  ForumWebEntry({required this.siteContext, DiscourseAuthManager? authManager})
      : _auth = authManager ?? DiscourseAuthManager(siteContext);

  final SiteContext siteContext;
  final DiscourseAuthManager _auth;

  /// Discourse's auth cookie. A deployment can rename it with
  /// DISCOURSE_TOKEN_COOKIE, which no ordinary install does; a renamed cookie
  /// only costs a redundant confirmation, never a wrong page.
  static const String authCookieName = '_t';

  /// Reads a cookie from the web view's own jar. Replaceable in tests —
  /// there is no platform web view under `flutter test`. Mirrors
  /// `AppearanceSync.writeCookie`.
  @visibleForTesting
  static Future<String?> Function(Uri origin, String name) readCookie =
      _readPlatformCookie;

  static Future<String?> _readPlatformCookie(Uri origin, String name) async {
    final cookie = await CookieManager.instance()
        .getCookie(url: WebUri(origin.toString()), name: name);
    final value = cookie?.value;
    return value == null ? null : '$value';
  }

  @visibleForTesting
  static void resetCookieReader() => readCookie = _readPlatformCookie;

  Uri _forumUri(String path) {
    final base = Uri.parse(siteContext.site.url);
    final basePath = base.path.endsWith('/')
        ? base.path.substring(0, base.path.length - 1)
        : base.path;
    final suffix = path.startsWith('/') ? path : '/$path';
    return base.replace(path: '$basePath$suffix');
  }

  /// The forum's own root, which is where Discourse lands a member after the
  /// confirmation POST.
  Uri get forumRoot => _forumUri('/');

  /// Works out how to open [path].
  ///
  /// Three outcomes, and two of them open the page directly:
  ///
  ///  * the web view already holds Discourse's auth cookie, so it is signed
  ///    in from an earlier visit — this is the ordinary case after the first
  ///    time, because the cookie outlives the page;
  ///  * no one-time password could be minted — signed out of the app, a
  ///    forum that does not allow the `one_time_password` scope, a member
  ///    outside `user_api_key_allowed_groups`, a failed request. The page
  ///    opens signed out, which is what it did before any of this existed;
  ///  * otherwise the confirmation page, with [ForumWebStart.target] carried
  ///    alongside.
  Future<ForumWebStart> start(String path) async {
    final target = _forumUri(path);
    ForumWebStart direct() => ForumWebStart(
          url: target,
          target: target,
          viaConfirmation: false,
        );

    final existing = await readCookie(target, authCookieName);
    if (existing != null && existing.isNotEmpty) return direct();

    final otpUrl = await _auth.oneTimeLoginUrl(
      applicationName: AppForumConfig.userApiApplicationName,
      authRedirect: AppForumConfig.userApiAuthRedirect,
    );
    if (otpUrl == null) return direct();

    return ForumWebStart(
      url: Uri.parse(otpUrl),
      target: target,
      viaConfirmation: true,
    );
  }

  /// Whether [visited] is the landing Discourse sends a member to once the
  /// confirmation POST has established the session, and so whether the view
  /// should now go on to the page that was asked for.
  ///
  /// Discourse redirects to the forum root from both successful branches —
  /// the POST that logs the member on, and the case where they were already
  /// signed in as that user. A confirmation that fails keeps them on the
  /// `/session/otp/` page with an error, where they belong: this returns
  /// false and the view stays put.
  bool isPostConfirmationLanding(Uri visited) {
    // Uri.origin throws on a scheme without an authority, and a web view
    // navigates to plenty of those (about:blank, intent://, the custom
    // scheme in our own auth_redirect).
    if (!visited.isScheme('http') && !visited.isScheme('https')) return false;
    if (!visited.hasAuthority) return false;

    final root = forumRoot;
    if (visited.origin != root.origin) return false;
    final seen = visited.path.endsWith('/') ? visited.path : '${visited.path}/';
    return seen == root.path;
  }
}
