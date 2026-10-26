import 'package:discourse_core/discourse_core.dart'
    show DiscourseSiteCapabilities;
import 'package:discourse_ui/l10n/generated/app_localizations.dart';
import 'package:discourse_ui/theme/app_theme.dart';
import 'package:discourse_ui/views/listitems/category_card.dart';
import 'package:discourse_ui/views/lists/posts_list.dart' show PostsListMode;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forumcopilot_sdk/forumcopilot_sdk.dart';

/// A category card says what is being discussed: its latest topic's title
/// and when it was last posted in, under the description, and a tap on it
/// opens that topic at its last post (the card itself opens the category).
void main() {
  const forum = 'https://forum.example';
  setUp(DiscourseSiteCapabilities.reset);

  SiteContext site() => SiteContext(
        siteType: 'discourse',
        site: Site(
          id: null,
          name: 'Test',
          url: forum,
          description: '',
          logoUrl: null,
          backgroundUrl: null,
          endpoint: null,
          baseUrl: forum,
          siteType: 'discourse',
        ),
      );

  Future<void> pump(WidgetTester tester) => tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: ListView(children: [
            CategoryCard(
              siteContext: site(),
              forum: FCForum(id: '5', name: 'Baking', description: 'Bread and cakes'),
            ),
            CategoryCard(siteContext: site(), forum: FCForum(id: '6', name: 'Quiet')),
          ]),
        ),
      ));

  void storeLatest() => DiscourseSiteCapabilities.storeCategoryActivity(forum, [
        {
          'id': 5,
          'topics': [
            {
              'id': 81,
              'title': 'Show us your bakes this week :bread:',
              'last_posted_at': DateTime.now()
                  .subtract(const Duration(hours: 3))
                  .toUtc()
                  .toIso8601String(),
              'highest_post_number': 45,
            },
          ],
        },
      ], withTopics: true);

  testWidgets('the latest topic shows under the description', (tester) async {
    final semantics = tester.ensureSemantics();
    storeLatest();
    await pump(tester);
    expect(find.byType(CategoryLatestTopicLine), findsOneWidget,
        reason: 'only the category that has one');
    expect(find.text('Show us your bakes this week 🍞'), findsOneWidget);
    final line = tester.getRect(find.byType(CategoryLatestTopicLine));
    expect(line.top, greaterThan(tester.getRect(find.text('Bread and cakes')).bottom - 1));
    expect(line.height, greaterThanOrEqualTo(40), reason: 'a finger\'s room');
    expect(
        find.bySemanticsLabel(RegExp(r'^Latest topic: Show us your bakes this week 🍞, .+')),
        findsOneWidget);
    semantics.dispose();
  });

  testWidgets('no topics, no line', (tester) async {
    await pump(tester);
    expect(find.byType(CategoryLatestTopicLine), findsNothing);
  });

  test('it opens at its last post', () {
    storeLatest();
    final topic = DiscourseSiteCapabilities.forSite(forum).latestTopics[5]!;
    final page = CategoryLatestTopicLine.pageFor(site(), topic, '5');
    expect(page.topicId, '81');
    expect(page.mode, PostsListMode.goto_page);
    expect(page.gotoPostNumber, 45);
    expect(page.gotoPage, 3, reason: 'posts 41–60 at 20 a page');
    expect(page.forumId, '5');
  });
}
