import 'package:discourse_core/discourse_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forumcopilot_sdk/forumcopilot_sdk.dart';

/// Each category card says what is being discussed: the latest of its
/// featured topics, which /categories.json carries in the same response
/// with include_topics, rather than a request per category.
void main() {
  const site = 'https://forum.example';
  setUp(DiscourseSiteCapabilities.reset);

  Map<String, dynamic> topic(int id, String title, String? at, {int highest = 1}) => {
        'id': id,
        'title': title,
        'slug': 'slug-$id',
        'last_posted_at': at,
        'highest_post_number': highest,
      };

  test('the latest is the most recently posted in, not the first listed', () {
    final latest = DiscourseCategoryLatestTopic.latestOf([
      topic(57, 'Welcome (pinned)', '2024-03-06T20:26:26Z'),
      topic(65, 'Avatars', '2025-09-21T13:01:53Z', highest: 4),
      topic(60, 'Under the title', '2024-03-08T06:05:00Z'),
      {'id': 'x', 'title': 'no id'},
      {'id': 70, 'title': '  '},
    ]);
    expect(latest?.id, 65);
    expect(latest?.title, 'Avatars');
    expect(latest?.slug, 'slug-65');
    expect(latest?.highestPostNumber, 4);
    expect(latest?.lastPostedAt, DateTime.utc(2025, 9, 21, 13, 1, 53));
    expect(DiscourseCategoryLatestTopic.latestOf(null), isNull);
    expect(DiscourseCategoryLatestTopic.latestOf(const []), isNull);
  });

  test('subcategories have their own; a list asked with topics replaces the last',
      () {
    DiscourseSiteCapabilities.storeCategoryActivity(site, [
      {
        'id': 1,
        'topics': [topic(10, 'In parent', '2026-10-01T00:00:00Z')],
        'subcategory_list': [
          {
            'id': 2,
            'topics': [topic(20, 'In sub', '2026-10-02T00:00:00Z')],
          },
        ],
      },
      {'id': 3},
    ], withTopics: true);
    final caps = DiscourseSiteCapabilities.forSite(site);
    expect(caps.latestTopics[1]?.title, 'In parent');
    expect(caps.latestTopics[2]?.title, 'In sub');
    expect(caps.latestTopics.containsKey(3), isFalse);

    // The drawer's list, without topics, leaves them be.
    DiscourseSiteCapabilities.storeCategoryActivity(site, [
      {'id': 1, 'topics_week': 4},
    ]);
    expect(caps.latestTopics[1]?.title, 'In parent');

    // The Categories view's next load: category 1 has none now.
    DiscourseSiteCapabilities.storeCategoryActivity(site, [
      {'id': 1},
    ], withTopics: true);
    expect(caps.latestTopics, isEmpty);
  });

  test('only the Categories view asks for topics', () async {
    final p = _Recording(site)
      ..response = {
        'category_list': {
          'categories': [
            {
              'id': 1,
              'name': 'General',
              'slug': 'general',
              'topics': [topic(10, 'Bakes this week', '2026-10-01T00:00:00Z')],
            },
          ],
        },
      };
    await p.getForumAsync(true, '', false);
    expect(p.query, {'include_subcategories': 'true'});
    expect(p.fresh, isFalse);
    await p.getForumAsync(true, '', true, includeLatestTopics: true);
    expect(p.query, {'include_subcategories': 'true', 'include_topics': 'true'});
    expect(p.fresh, isTrue,
        reason: 'a pull to refresh skips the five-minute read cache');
    expect(DiscourseSiteCapabilities.forSite(site).latestTopics[1]?.title,
        'Bakes this week');
  });
}

class _Recording extends DiscourseForumProxy {
  _Recording(String url)
      : super(SiteContext(
          siteType: 'discourse',
          site: Site(
            id: null,
            name: 'Test',
            url: url,
            description: '',
            endpoint: null,
            baseUrl: url,
            logoUrl: null,
            backgroundUrl: null,
            siteType: 'discourse',
          ),
        ));

  Map<String, dynamic>? query;
  bool fresh = false;
  Map<String, dynamic> response = const {};

  @override
  Future<Map<String, dynamic>> apiGet(String path, {Map<String, dynamic>? query}) async {
    expect(path, '/categories.json');
    this.query = query;
    fresh = false;
    return response;
  }

  @override
  Future<Map<String, dynamic>> apiGetFresh(String path, {Map<String, dynamic>? query}) async {
    expect(path, '/categories.json');
    this.query = query;
    fresh = true;
    return response;
  }
}
