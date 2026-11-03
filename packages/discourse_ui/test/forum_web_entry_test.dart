import 'package:discourse_core/discourse_core.dart';
import 'package:discourse_ui/services/forum_web_entry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forumcopilot_sdk/forumcopilot_sdk.dart';

/// Which URL a web view opens for a forum page, and when it has to go on
/// somewhere afterwards.
///
/// The real flow needs a platform web view and a person's tap, neither of
/// which exists under `flutter test`, so the decision is a plain object and
/// this exercises it directly.
void main() {
  const url = 'https://forum.example';

  SiteContext contextFor(String site) => SiteContext(
        siteType: 'discourse',
        site: Site(
          id: null,
          name: 'Example',
          url: site,
          description: 'web entry test site',
          endpoint: null,
          baseUrl: site,
          logoUrl: null,
          backgroundUrl: null,
          siteType: 'discourse',
        ),
      );

  ForumWebEntry entryFor({
    String site = url,
    String? cookie,
    String? otpUrl = '$url/session/otp/abc123',
  }) {
    ForumWebEntry.readCookie = (origin, name) async {
      expect(name, '_t', reason: "Discourse's auth cookie");
      return cookie;
    };
    return ForumWebEntry(
      siteContext: contextFor(site),
      authManager: _Auth(contextFor(site), otpUrl),
    );
  }

  tearDown(ForumWebEntry.resetCookieReader);

  group('start', () {
    test('a web view that already holds the session opens the page itself',
        () async {
      final auth = _Auth(contextFor(url), '$url/session/otp/abc123');
      ForumWebEntry.readCookie = (_, __) async => 'an-existing-token';
      final entry = ForumWebEntry(
        siteContext: contextFor(url),
        authManager: auth,
      );

      final start = await entry.start('/matchmaking');

      expect(start.viaConfirmation, isFalse);
      expect(start.url, Uri.parse('$url/matchmaking'));
      expect(auth.minted, 0,
          reason: 'the cookie outlives the page, so after the first visit '
              'there is nothing to mint and nothing to confirm');
    });

    test('without the session it opens the confirmation page, carrying the '
        'page that was asked for', () async {
      final start = await entryFor().start('/matchmaking');

      expect(start.viaConfirmation, isTrue);
      expect(start.url, Uri.parse('$url/session/otp/abc123'));
      expect(start.target, Uri.parse('$url/matchmaking'));
    });

    test('a forum that will not mint opens the page signed out', () async {
      // No key, a forum whose allow_user_api_key_scopes omits
      // one_time_password, a member outside user_api_key_allowed_groups, a
      // dead network. The page is still worth showing.
      final start = await entryFor(cookie: null, otpUrl: null)
          .start('/matchmaking');

      expect(start.viaConfirmation, isFalse);
      expect(start.url, Uri.parse('$url/matchmaking'));
    });

    test('a path without its leading slash still lands on the page', () async {
      final start = await entryFor(cookie: 'tok').start('matchmaking');
      expect(start.url, Uri.parse('$url/matchmaking'));
    });

    test('a subfolder install keeps its subfolder', () async {
      const sub = 'https://example.com/forum';
      final start =
          await entryFor(site: sub, cookie: 'tok').start('/matchmaking');

      expect(start.url, Uri.parse('$sub/matchmaking'));
      expect(
        ForumWebEntry(siteContext: contextFor(sub)).forumRoot,
        Uri.parse('$sub/'),
      );
    });
  });

  group('isPostConfirmationLanding', () {
    final entry = ForumWebEntry(siteContext: contextFor(url));

    test('the forum root is the landing Discourse sends them to', () {
      expect(entry.isPostConfirmationLanding(Uri.parse('$url/')), isTrue);
      expect(entry.isPostConfirmationLanding(Uri.parse(url)), isTrue,
          reason: 'with or without the trailing slash');
    });

    test('the confirmation page itself is not the landing', () {
      // A confirmation that fails keeps them here with an error, which is
      // where they belong — the view must not jump away from it.
      expect(
        entry.isPostConfirmationLanding(Uri.parse('$url/session/otp/abc123')),
        isFalse,
      );
    });

    test('another forum, or another page, is not the landing', () {
      expect(entry.isPostConfirmationLanding(Uri.parse('$url/latest')), isFalse);
      expect(
        entry.isPostConfirmationLanding(Uri.parse('https://elsewhere.test/')),
        isFalse,
      );
    });

    test('a scheme with no authority does not throw', () {
      // Uri.origin throws on these, and a web view navigates to plenty of
      // them: about:blank, an intent:// handoff, our own auth_redirect.
      expect(entry.isPostConfirmationLanding(Uri.parse('about:blank')), isFalse);
      expect(
        entry.isPostConfirmationLanding(Uri.parse('discourse://auth_redirect')),
        isFalse,
      );
      expect(entry.isPostConfirmationLanding(Uri.parse('')), isFalse);
    });

    test("a subfolder forum's root is the subfolder, not the host", () {
      const sub = 'https://example.com/forum';
      final subEntry = ForumWebEntry(siteContext: contextFor(sub));

      expect(subEntry.isPostConfirmationLanding(Uri.parse('$sub/')), isTrue);
      expect(
        subEntry.isPostConfirmationLanding(Uri.parse('https://example.com/')),
        isFalse,
        reason: 'the host root is a different site to a subfolder install',
      );
    });
  });
}

/// Stands in for the mint, which needs a network and a real key.
class _Auth extends DiscourseAuthManager {
  _Auth(SiteContext context, this._url) : super(context);

  final String? _url;
  int minted = 0;

  @override
  Future<String?> oneTimeLoginUrl({
    required String applicationName,
    required String authRedirect,
  }) async {
    minted++;
    return _url;
  }
}
