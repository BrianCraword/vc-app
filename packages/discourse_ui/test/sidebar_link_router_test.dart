import 'package:discourse_core/discourse_core.dart';
import 'package:discourse_ui/services/sidebar_link_router.dart';
import 'package:flutter_test/flutter_test.dart';

/// Where each sidebar link goes: the app's own screen where it has one, the
/// signed-in web view for the forum's own pages, the system browser for
/// anything off the forum.
void main() {
  DiscourseSidebarLink link(String value,
          {bool external = false, String name = 'Link'}) =>
      DiscourseSidebarLink(id: 1, name: name, value: value, external: external);

  group("Discourse's built-in links the app renders itself", () {
    const cases = {
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

    cases.forEach((path, screen) {
      test('$path is native', () {
        expect(routeSidebarLink(link(path)), SidebarNative(screen));
      });
    });
  });

  test('built-ins the app has no screen for open on the web, not nowhere', () {
    // /admin, /new-invite, /faq and /filter are built-in community links
    // too. Dropping them would make a link the forum shows do nothing.
    for (final path in ['/admin', '/new-invite', '/faq', '/filter']) {
      expect(routeSidebarLink(link(path)), SidebarWeb(path), reason: path);
    }
  });

  group("the forum's own pages", () {
    test('a plugin page opens in the signed-in web view', () {
      expect(routeSidebarLink(link('/feed')), const SidebarWeb('/feed'));
      expect(routeSidebarLink(link('/matchmaking')),
          const SidebarWeb('/matchmaking'));
    });

    test('a trailing slash is not a different page', () {
      // A forum can save it either way; Victorious Christians stores
      // Scripture Campaign with one.
      expect(
        routeSidebarLink(link('/scripture-campaign/')),
        const SidebarWeb('/scripture-campaign'),
      );
    });

    test('a query or fragment is dropped before matching', () {
      expect(routeSidebarLink(link('/latest?order=created')),
          const SidebarNative(SidebarNativeScreen.latest));
      expect(routeSidebarLink(link('/about#staff')),
          const SidebarNative(SidebarNativeScreen.about));
    });

    test('a value without its leading slash still resolves', () {
      expect(routeSidebarLink(link('feed')), const SidebarWeb('/feed'));
    });
  });

  group('category links', () {
    test('open the native category, not a web view', () {
      expect(routeSidebarLink(link('/c/blog/107')), const SidebarCategory(107));
    });

    test('a subcategory is named by its own id, the last one', () {
      expect(
        routeSidebarLink(link('/c/site-feedback/tutorials/105')),
        const SidebarCategory(105),
      );
    });

    test('a category link with no id is just a page', () {
      expect(routeSidebarLink(link('/c/blog')), const SidebarWeb('/c/blog'));
    });
  });

  group('external links', () {
    test('go to the system browser, not a view holding the session', () {
      expect(
        routeSidebarLink(link('https://victoriouschristians.com', external: true)),
        SidebarExternal(Uri.parse('https://victoriouschristians.com')),
      );
    });

    test('a non-web scheme is not handed to the browser', () {
      // Discourse validates these, but a stored value can still be junk,
      // and about:blank or javascript: must never be opened.
      expect(
        routeSidebarLink(link('javascript:alert(1)', external: true)),
        isA<SidebarWeb>(),
      );
    });
  });
}
