import 'package:discourse_core/discourse_core.dart';
import 'package:flutter_test/flutter_test.dart';

/// Reading a forum's own sidebar out of the payloads the app already fetches.
///
/// Fixtures are the real shape Victorious Christians serves, trimmed.
void main() {
  const site = 'https://forum.example';

  Map<String, Object?> link(
    int id,
    String name,
    String value, {
    String? icon,
    bool external = false,
    String segment = 'primary',
  }) =>
      {
        'id': id,
        'name': name,
        'value': value,
        'icon': icon,
        'external': external,
        'segment': segment,
      };

  List<Object?> community() => [
        {
          'id': 1,
          'title': 'Community',
          'slug': 'community',
          'public': true,
          'section_type': 'community',
          'links': [
            link(1, 'Feed', '/feed', icon: 'rss'),
            link(2, 'Scripture Campaign', '/scripture-campaign/', icon: 'book'),
            link(3, 'FAQ', '/faq', segment: 'secondary'),
          ],
        },
      ];

  setUp(DiscourseSidebarSections.reset);

  test('reads a section and splits its links by segment', () {
    DiscourseSidebarSections.storeFromSite(site, community());

    final sections = DiscourseSidebarSections.forSite(site);
    expect(sections, hasLength(1));
    final s = sections.single;
    expect(s.title, 'Community');
    expect(s.isCommunity, isTrue);
    expect(s.primaryLinks.map((l) => l.name), ['Feed', 'Scripture Campaign']);
    expect(s.secondaryLinks.map((l) => l.name), ['FAQ']);
    expect(s.links.first.icon, 'rss');
    expect(s.links.first.external, isFalse);
  });

  test("the member's own sidebar wins over the forum's defaults", () {
    DiscourseSidebarSections.storeFromSite(site, community());
    DiscourseSidebarSections.storeFromCurrentUser(site, [
      {
        'id': 9,
        'title': 'Mine',
        'section_type': null,
        'links': [link(9, 'Matchmaking', '/matchmaking')],
      },
    ]);

    expect(DiscourseSidebarSections.forSite(site).single.title, 'Mine',
        reason: 'the web shows a signed-in member their own sections');
  });

  test('signing out drops the member but keeps the forum', () {
    DiscourseSidebarSections.storeFromSite(site, community());
    DiscourseSidebarSections.storeFromCurrentUser(site, [
      {'id': 9, 'title': 'Mine', 'links': [link(9, 'X', '/x')]},
    ]);

    DiscourseSidebarSections.clearOwn(site);

    expect(DiscourseSidebarSections.forSite(site).single.title, 'Community',
        reason: "the defaults are the forum's, not the member's");
  });

  test('a link missing what it needs is skipped, the rest survive', () {
    DiscourseSidebarSections.storeFromSite(site, [
      {
        'id': 1,
        'title': 'Community',
        'links': [
          {'id': 1, 'name': 'Good', 'value': '/good'},
          {'id': 2, 'name': '', 'value': '/no-name'},
          {'id': 3, 'name': 'No value', 'value': ''},
          {'name': 'No id', 'value': '/no-id'},
          'not a map',
        ],
      },
    ]);

    expect(
      DiscourseSidebarSections.forSite(site).single.links.map((l) => l.name),
      ['Good'],
    );
  });

  test('a payload that parses to nothing does not empty a good sidebar', () {
    DiscourseSidebarSections.storeFromSite(site, community());
    // A shape we do not understand, or a section with no usable links.
    DiscourseSidebarSections.storeFromSite(site, [
      {'nonsense': true},
    ]);

    expect(DiscourseSidebarSections.forSite(site), hasLength(1),
        reason: 'overwriting with an unreadable payload would blank the '
            'drawer for no reason');
  });

  test('a forum with genuinely no sections reads as none', () {
    DiscourseSidebarSections.storeFromSite(site, community());
    DiscourseSidebarSections.storeFromSite(site, const []);

    expect(DiscourseSidebarSections.forSite(site), isEmpty,
        reason: 'an empty list is a real answer, unlike an unreadable one');
  });

  test('an unread forum has nothing rather than throwing', () {
    expect(DiscourseSidebarSections.forSite(site), isEmpty);
  });

  test('sections are kept apart per forum', () {
    DiscourseSidebarSections.storeFromSite(site, community());
    expect(DiscourseSidebarSections.forSite('https://other.example'), isEmpty);
  });
}
