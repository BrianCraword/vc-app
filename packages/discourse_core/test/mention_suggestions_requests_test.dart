import 'package:discourse_core/discourse_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forumcopilot_sdk/forumcopilot_sdk.dart';

/// What the post composer asks for when `@` is typed: the web composer's
/// mention search, scoped to the topic (or a new topic's category) so its
/// posters come first.
void main() {
  const site = 'https://forum.example';

  test('@ alone in a reply asks for the topic\'s people, the replied-to '
      'author first', () async {
    final p = _Recording(site)
      ..response = {
        'users': [
          {'username': 'samr', 'name': 'Sam Rivera', 'avatar_template': '/a/{size}.png'},
          {'username': 'jo'},
        ],
      };
    final people = await p.searchMentionsAsync('', topicId: 42, prioritizedUserId: 7);
    expect(p.query, {
      'term': '',
      'topic_id': '42',
      'prioritized_user_id': '7',
      'limit': '6',
    }, reason: 'no groups for an empty term, as the server sends none');
    expect(people.map((u) => (u.username, u.name, u.isGroup)),
        [('samr', 'Sam Rivera', false), ('jo', null, false)]);
    expect(people.first.avatarUrl, '$site/a/48.png');
  });

  test('a term brings the groups the viewer may mention', () async {
    final p = _Recording(site)
      ..response = {
        'users': [
          {'username': 'samr'},
        ],
        'groups': [
          {'name': 'team', 'full_name': 'The Team'},
          {'name': ''},
        ],
      };
    final people = await p.searchMentionsAsync('sa', categoryId: 5);
    expect(p.query?['category_id'], '5');
    expect(p.query?['include_mentionable_groups'], 'true');
    expect(p.query?.containsKey('include_groups'), isFalse,
        reason: 'only groups that can be mentioned');
    expect(people.map((u) => (u.username, u.isGroup)),
        [('samr', false), ('team', true)]);
  });

  test('an empty term with no topic or category is not asked', () async {
    final p = _Recording(site);
    expect(await p.searchMentionsAsync(''), isEmpty);
    expect(p.query, isNull);
  });

  test('enable_mentions: on unless the forum turns it off', () {
    DiscourseSiteCapabilities.reset();
    expect(DiscourseSiteCapabilities.forSite(site).enableMentions, isTrue,
        reason: 'before the settings have loaded');
    DiscourseSiteCapabilities.storeClientSettings(site, {'enable_mentions': false});
    expect(DiscourseSiteCapabilities.forSite(site).enableMentions, isFalse);
    DiscourseSiteCapabilities.storeClientSettings(site, {});
    expect(DiscourseSiteCapabilities.forSite(site).enableMentions, isTrue);
  });

  test('a failed search is no suggestions', () async {
    final p = _Recording(site)..fail = true;
    expect(await p.searchMentionsAsync('sa', topicId: 1), isEmpty);
  });
}

class _Recording extends DiscourseUserProxy {
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
  Map<String, dynamic> response = const {};
  bool fail = false;

  @override
  Future<Map<String, dynamic>> apiGet(String path, {Map<String, dynamic>? query}) async {
    expect(path, '/u/search/users.json');
    this.query = query;
    if (fail) throw Exception('offline');
    return response;
  }
}
