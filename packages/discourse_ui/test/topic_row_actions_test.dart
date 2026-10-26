import 'package:discourse_core/discourse_core.dart'
    show DiscourseBookmarkProxy, DiscourseTopicProxy, DiscourseTopicTracking;
import 'package:discourse_ui/l10n/generated/app_localizations.dart';
import 'package:discourse_ui/views/listitems/topic_list_item.dart';
import 'package:discourse_ui/views/widgets/topic_actions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forumcopilot_sdk/forumcopilot_sdk.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A topic row answers more than a tap, as the Flarum app's discussion rows
/// do: swipe a new or unread one to dismiss it (it stays in the list), and
/// long-press any row for Dismiss, its notification level, its bookmark,
/// Share and Copy link.
void main() {
  const url = 'https://rows.example';
  late SiteContext ctx;
  late List<String> calls;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    DiscourseTopicTracking.clearAll();
    calls = [];
    ctx = SiteContext(
      siteType: 'discourse',
      site: Site(
        id: null,
        name: 'Example',
        url: url,
        description: '',
        endpoint: null,
        baseUrl: url,
        logoUrl: null,
        backgroundUrl: null,
        siteType: 'discourse',
      ),
    )..setLoginData(FCLoginResult(
        result: true, resultText: '', user: FCUser(id: '2', username: 'alice')));
    TopicActions.debugTopicProxy = (site) => _Topics(site, calls);
    TopicActions.debugBookmarkProxy = (site) => _Bookmarks(site, calls);
  });

  tearDown(() {
    TopicActions.debugTopicProxy = null;
    TopicActions.debugBookmarkProxy = null;
  });

  FCTopic topic(String id) => FCTopic(
        id: id,
        title: 'Topic $id',
        forumId: '4',
        forumName: '',
        authorId: '1',
        authorName: 'bob',
        timestamp: DateTime(2026, 9, 1),
      );

  void record(String id,
          {int? lastRead, int highest = 5, int? level, bool unseen = false, bool? bookmarked}) =>
      DiscourseTopicTracking.forSite(ctx).recordTopicJson({
        'id': int.parse(id),
        'highest_post_number': highest,
        if (lastRead != null) 'last_read_post_number': lastRead,
        if (level != null) 'notification_level': level,
        'unseen': unseen,
        if (bookmarked != null) 'bookmarked': bookmarked,
      });

  Future<void> pumpRows(WidgetTester tester, List<String> ids) async {
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: ListView(children: [
          for (final id in ids)
            TopicListItem(siteContext: ctx, topic: topic(id), onTap: () {}),
        ]),
      ),
    ));
    await tester.pump();
  }

  testWidgets('swiping a new topic dismisses it, and the row stays',
      (tester) async {
    record('1', unseen: true); // new
    record('2', lastRead: 3, level: 2); // two unread
    record('3', lastRead: 5, level: 2); // read
    await pumpRows(tester, ['1', '2', '3']);
    expect(find.byType(Dismissible), findsNWidgets(2),
        reason: 'only new and unread rows swipe');

    await tester.drag(find.text('Topic 1'), const Offset(-500, 0));
    await tester.pumpAndSettle();
    expect(calls, [
      'PUT /topics/bulk dismiss_posts [1]',
      'PUT /topics/bulk dismiss_topics [1]',
    ]);
    expect(find.text('Topic 1'), findsOneWidget, reason: 'it stays');
    expect(DiscourseTopicTracking.forSite(ctx).stateOf('1')!.isNew, isFalse);
    expect(find.byType(Dismissible), findsOneWidget,
        reason: 'nothing left to dismiss on it');
  });

  testWidgets('a guest\'s rows do not swipe, and long-press offers sharing',
      (tester) async {
    record('1', unseen: true);
    ctx.setLoginData(null);
    await pumpRows(tester, ['1']);
    expect(find.byType(Dismissible), findsNothing);

    await tester.longPress(find.text('Topic 1'));
    await tester.pumpAndSettle();
    expect(find.text('Share'), findsOneWidget);
    expect(find.text('Copy link'), findsOneWidget);
    expect(find.text('Dismiss'), findsNothing);
    expect(find.text('Notifications'), findsNothing);
    expect(find.text('Bookmark topic'), findsNothing);
  });

  testWidgets('long-press: Dismiss, the level, the bookmark, Share, Copy link',
      (tester) async {
    record('2', lastRead: 3, level: 2, bookmarked: false);
    await pumpRows(tester, ['2']);
    await tester.longPress(find.text('Topic 2'));
    await tester.pumpAndSettle();

    expect(find.text('Dismiss'), findsOneWidget);
    expect(find.text('Notifications'), findsOneWidget);
    expect(
        find.descendant(
            of: find.byType(BottomSheet), matching: find.text('Tracking')),
        findsOneWidget,
        reason: 'the level now');
    expect(find.text('Share'), findsOneWidget);

    await tester.tap(find.text('Bookmark topic'));
    await tester.pumpAndSettle();
    expect(calls, ['POST /bookmarks.json Topic 2']);
    expect(find.text('Topic bookmarked'), findsOneWidget);
    expect(DiscourseTopicTracking.forSite(ctx).stateOf('2')!.bookmarked, isTrue);
  });

  testWidgets('a bookmarked topic asks before deleting its bookmarks',
      (tester) async {
    record('2', lastRead: 5, level: 1, bookmarked: true);
    await pumpRows(tester, ['2']);
    await tester.longPress(find.text('Topic 2'));
    await tester.pumpAndSettle();
    expect(find.text('Dismiss'), findsNothing, reason: 'it is read');

    await tester.tap(find.text('Delete all bookmarks'));
    await tester.pumpAndSettle();
    expect(find.text('Delete all your bookmarks in this topic? Their '
        'reminders go too.'), findsOneWidget);
    expect(calls, isEmpty);

    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(calls, ['PUT /t/2/remove_bookmarks.json']);
    expect(find.text('Bookmarks deleted'), findsOneWidget);
  });

  testWidgets('Copy link copies the topic\'s web address', (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map)['text'] as String?;
      }
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    record('2', lastRead: 5, level: 1);
    await pumpRows(tester, ['2']);
    await tester.longPress(find.text('Topic 2'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Copy link'));
    await tester.pumpAndSettle();
    expect(copied, '$url/t/topic/2');
    expect(find.text('Link copied'), findsOneWidget);
  });
}

class _Topics extends DiscourseTopicProxy {
  _Topics(super.context, this.calls);
  final List<String> calls;

  @override
  Future<Map<String, dynamic>> apiPut(String path,
      {Map<String, dynamic>? query, Object? body}) async {
    final b = body as Map;
    calls.add('PUT $path ${(b['operation'] as Map)['type']} ${b['topic_ids']}');
    return const {};
  }
}

class _Bookmarks extends DiscourseBookmarkProxy {
  _Bookmarks(super.context, this.calls);
  final List<String> calls;

  @override
  Future<Map<String, dynamic>> apiPost(String path,
      {Map<String, dynamic>? query, Object? body}) async {
    final b = body as Map;
    calls.add('POST $path ${b['bookmarkable_type']} ${b['bookmarkable_id']}');
    return {'id': 9};
  }

  @override
  Future<Map<String, dynamic>> apiPut(String path,
      {Map<String, dynamic>? query, Object? body}) async {
    calls.add('PUT $path');
    return const {};
  }
}
