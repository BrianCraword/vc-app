import 'package:discourse_core/discourse_core.dart';
import 'package:flutter/foundation.dart';

/// A screen the app renders itself, so the matching sidebar link should not
/// open a web view.
enum SidebarNativeScreen {
  latest,
  myPosts,
  myMessages,
  review,
  users,
  about,
  groups,
  badges,
  categories,
}

/// Where a sidebar link should take the member.
@immutable
sealed class SidebarDestination {
  const SidebarDestination();
}

/// The app has this screen. Preferred wherever it exists: a native screen
/// scrolls, themes and navigates like the rest of the app.
final class SidebarNative extends SidebarDestination {
  const SidebarNative(this.screen);
  final SidebarNativeScreen screen;

  @override
  bool operator ==(Object other) =>
      other is SidebarNative && other.screen == screen;
  @override
  int get hashCode => screen.hashCode;
  @override
  String toString() => 'SidebarNative(${screen.name})';
}

/// A category the app can open natively, named by a `/c/…/<id>` link.
final class SidebarCategory extends SidebarDestination {
  const SidebarCategory(this.categoryId);
  final int categoryId;

  @override
  bool operator ==(Object other) =>
      other is SidebarCategory && other.categoryId == categoryId;
  @override
  int get hashCode => categoryId.hashCode;
  @override
  String toString() => 'SidebarCategory($categoryId)';
}

/// A forum page the app does not render — the Feed's own views, Scripture
/// Campaign, matchmaking, anything a theme component draws. Opened in the
/// signed-in web view.
final class SidebarWeb extends SidebarDestination {
  const SidebarWeb(this.path);

  /// A forum path, without the forum's subfolder: the web view prefixes it.
  final String path;

  @override
  bool operator ==(Object other) => other is SidebarWeb && other.path == path;
  @override
  int get hashCode => path.hashCode;
  @override
  String toString() => 'SidebarWeb($path)';
}

/// Somewhere off the forum. Discourse marks these itself, and they belong in
/// the system browser rather than a view carrying the member's session.
final class SidebarExternal extends SidebarDestination {
  const SidebarExternal(this.url);
  final Uri url;

  @override
  bool operator ==(Object other) =>
      other is SidebarExternal && other.url == url;
  @override
  int get hashCode => url.hashCode;
  @override
  String toString() => 'SidebarExternal($url)';
}

/// Discourse's own built-in community links, by path.
///
/// Taken from `SidebarUrl::COMMUNITY_SECTION_LINKS`. Only the ones the app
/// actually has a screen for are here: `/admin`, `/new-invite`, `/faq` and
/// `/filter` are built-in too and deliberately absent, so they open in the
/// web view rather than silently going nowhere.
const Map<String, SidebarNativeScreen> _builtIn = {
  '/latest': SidebarNativeScreen.latest,
  '/my/activity': SidebarNativeScreen.myPosts,
  '/my/messages': SidebarNativeScreen.myMessages,
  '/review': SidebarNativeScreen.review,
  '/u': SidebarNativeScreen.users,
  '/about': SidebarNativeScreen.about,
  '/g': SidebarNativeScreen.groups,
  '/badges': SidebarNativeScreen.badges,
  '/categories': SidebarNativeScreen.categories,
};

/// Discourse category links end in the category's id: `/c/blog/107`,
/// `/c/site-feedback/tutorials/105` for a subcategory.
final RegExp _categoryPath = RegExp(r'^/c/(?:[^/]+/)*(\d+)$');

/// Decides where a sidebar link goes.
///
/// A native screen wherever the app has one, because a web view is a visible
/// seam — different scrolling, different type, a second loading spinner. The
/// web view is for the pages that only exist on the web, which is the whole
/// reason the forum's sidebar is worth reading in the first place.
SidebarDestination routeSidebarLink(DiscourseSidebarLink link) {
  final raw = link.value.trim();

  if (link.external) {
    final uri = Uri.tryParse(raw);
    // Discourse validates these, but a stored value can still be junk, and
    // a link that goes nowhere is better than one that opens about:blank.
    if (uri != null && (uri.isScheme('http') || uri.isScheme('https'))) {
      return SidebarExternal(uri);
    }
    return SidebarWeb(_normalise(raw));
  }

  final path = _normalise(raw);

  final native = _builtIn[path];
  if (native != null) return SidebarNative(native);

  final category = _categoryPath.firstMatch(path);
  if (category != null) {
    final id = int.tryParse(category.group(1)!);
    if (id != null) return SidebarCategory(id);
  }

  return SidebarWeb(path);
}

/// A sidebar value is a path as the forum stored it, which is not
/// necessarily tidy: a forum can save `/scripture-campaign/` with its
/// trailing slash, and a built-in can arrive with a query on it.
String _normalise(String value) {
  var path = value;
  final hash = path.indexOf('#');
  if (hash >= 0) path = path.substring(0, hash);
  final query = path.indexOf('?');
  if (query >= 0) path = path.substring(0, query);
  if (path.length > 1 && path.endsWith('/')) {
    path = path.substring(0, path.length - 1);
  }
  if (path.isEmpty) return '/';
  return path.startsWith('/') ? path : '/$path';
}
