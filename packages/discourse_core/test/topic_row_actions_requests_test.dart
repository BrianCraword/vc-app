import 'dart:convert';

import 'package:discourse_core/discourse_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forumcopilot_sdk/forumcopilot_sdk.dart';

/// What a topic row's swipe and long-press sheet send: the web's Dismiss
/// for one topic, the topic's own bookmark, and its notification level,
/// each reflected at once in the store the row reads.
void main() {
  const url = 'https://forum.example';
  late SiteContext ctx;
  late List<String> calls;

  setUp(() {
    DiscourseTopicTracking.clearAll();
    calls = [];
    ctx = SiteContext(
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
    )..setLoginData(FCLoginResult(
        result: true, resultText: '', user: FCUser(id: '2', username: 'alice')));
  });

  DiscourseTopicTracking tracking() => DiscourseTopicTracking.forSite(ctx);

  void seed() {
    // 10: never opened, new. 11: opened, two replies unread, tracked.
    tracking().recordTopicJson(
        {'id': 10, 'highest_post_number': 3, 'unseen': true, 'bookmarked': false});
    tracking().recordTopicJson({
      'id': 11,
      'highest_post_number': 5,
      'last_read_post_number': 3,
      'notification_level': 2,
      'bookmarked': true,
    });
  }

  test('Dismiss sends both of the web\'s operations, so a topic never '
      'opened stops being new too', () async {
    seed();
    expect(tracking().stateOf('10')!.isNew, isTrue);
    expect(tracking().stateOf('11')!.unreadCount, 2);

    final r = await _Topics(ctx, calls).markTopicReadAsync(['10', '11']);
    expect(r.result, isTrue);
    expect(calls, [
      'PUT /topics/bulk {"topic_ids":[10,11],"operation":{"type":"dismiss_posts"}}',
      'PUT /topics/bulk {"topic_ids":[10,11],"operation":{"type":"dismiss_topics"}}',
    ]);
    expect(tracking().stateOf('10')!.isNew, isFalse);
    expect(tracking().stateOf('10')!.lastReadPostNumber, isNull,
        reason: 'dismissed, not read: the server moves no place it has none '
            'of, and the row stays bold as after a reload');
    expect(tracking().stateOf('11')!.unreadCount, 0);
    expect(tracking().stateOf('11')!.lastReadPostNumber, 5);
  });

  test('a list says whether the viewer bookmarked the topic', () {
    seed();
    expect(tracking().stateOf('10')!.bookmarked, isFalse);
    expect(tracking().stateOf('11')!.bookmarked, isTrue);
    // A payload without the field leaves it as it was.
    tracking().recordTopicJson({'id': 11, 'highest_post_number': 6});
    expect(tracking().stateOf('11')!.bookmarked, isTrue);
  });

  test('bookmark the topic; delete all its bookmarks', () async {
    seed();
    final p = _Bookmarks(ctx, calls);
    final added = await p.addTopicBookmarkAsync('10');
    expect(added.result, isTrue);
    expect(added.bookmarkId, 77);
    expect(tracking().stateOf('10')!.bookmarked, isTrue);

    final removed = await p.deleteTopicBookmarksAsync('11');
    expect(removed.result, isTrue);
    expect(tracking().stateOf('11')!.bookmarked, isFalse);
    expect(calls, [
      'POST /bookmarks.json {"bookmarkable_type":"Topic","bookmarkable_id":10}',
      'PUT /t/11/remove_bookmarks.json',
    ]);
  });

  test('a new level shows at once: below Tracking, nothing unread', () async {
    seed();
    final r = await _Levels(ctx, calls)
        .setTopicNotificationLevelAsync('11', FCNotificationLevel.normal);
    expect(r.result, isTrue);
    expect(calls, ['POST /t/11/notifications.json {"notification_level":1}']);
    expect(tracking().stateOf('11')!.notificationLevel, 1);
    expect(tracking().stateOf('11')!.unreadCount, 0);
  });
}

String _call(String method, String path, Object? body) =>
    '$method $path${body == null ? '' : ' ${jsonEncode(body)}'}';

class _Topics extends DiscourseTopicProxy {
  _Topics(super.context, this.calls);
  final List<String> calls;

  @override
  Future<Map<String, dynamic>> apiPut(String path, {Map<String, dynamic>? query, Object? body}) async {
    calls.add(_call('PUT', path, body));
    return const {};
  }
}

class _Bookmarks extends DiscourseBookmarkProxy {
  _Bookmarks(super.context, this.calls);
  final List<String> calls;

  @override
  Future<Map<String, dynamic>> apiPost(String path, {Map<String, dynamic>? query, Object? body}) async {
    calls.add(_call('POST', path, body));
    return {'id': 77};
  }

  @override
  Future<Map<String, dynamic>> apiPut(String path, {Map<String, dynamic>? query, Object? body}) async {
    calls.add(_call('PUT', path, body));
    return const {};
  }
}

class _Levels extends DiscourseSubscriptionProxy {
  _Levels(super.context, this.calls);
  final List<String> calls;

  @override
  Future<Map<String, dynamic>> apiPost(String path, {Map<String, dynamic>? query, Object? body}) async {
    calls.add(_call('POST', path, body));
    return const {};
  }
}
