import 'package:discourse_core/discourse_core.dart'
    show DiscourseMentionCandidate;
import 'package:discourse_ui/utils/mention_suggester.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forumcopilot_sdk/models/entities/fc_post.dart';

/// Typing `@` in the composer offers the topic's people at once, and the
/// forum's matches from the second letter, as the Flarum app does; the
/// mention picker page was three steps for replying to someone in the
/// thread.
void main() {
  DiscourseMentionCandidate person(String username, {String? name}) =>
      (username: username, name: name, avatarUrl: null, isGroup: false);

  TextEditingValue typed(String text, [int? cursor]) => TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: cursor ?? text.length));

  Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 20));

  group('the @name before the cursor', () {
    test('at the start, after a space or a bracket', () {
      expect(MentionSuggester.mentionAt(typed('@')), (start: 0, query: ''));
      expect(MentionSuggester.mentionAt(typed('hi @sa')), (start: 3, query: 'sa'));
      expect(MentionSuggester.mentionAt(typed('(@jo.d-x')), (start: 1, query: 'jo.d-x'));
      expect(MentionSuggester.mentionAt(typed('hi @Zoë')), (start: 3, query: 'Zoë'));
    });

    test('not an email address, a finished mention, or a selection', () {
      expect(MentionSuggester.mentionAt(typed('me@example')), isNull);
      expect(MentionSuggester.mentionAt(typed('@sam ')), isNull);
      expect(MentionSuggester.mentionAt(const TextEditingValue(
              text: 'hi @sam',
              selection: TextSelection(baseOffset: 3, extentOffset: 7))),
          isNull);
    });

    test('where the cursor is, not at the end of the text', () {
      expect(MentionSuggester.mentionAt(typed('hi @sa and more', 6)),
          (start: 3, query: 'sa'));
    });

    test('completing puts the mention and a space in its place', () {
      final done = MentionSuggester.complete(
          typed('thanks @sa and more', 10), person('samr'));
      expect(done?.text, 'thanks @samr  and more');
      expect(done?.selection.baseOffset, 13);
      expect(MentionSuggester.complete(typed('no mention'), person('samr')),
          isNull);
    });
  });

  group('what is offered', () {
    late List<String> asked;
    late Map<String, List<DiscourseMentionCandidate>> answers;

    MentionSuggester suggester({
      List<DiscourseMentionCandidate> people = const [],
      String? self,
    }) {
      asked = [];
      answers = {};
      return MentionSuggester(
        search: (term) async {
          asked.add(term);
          return answers[term] ?? const [];
        },
        people: people,
        selfUsername: self,
        debounce: const Duration(milliseconds: 1),
      );
    }

    List<String> names(MentionSuggester s) =>
        [for (final c in s.suggestions) c.username];

    test('@ alone: the topic\'s people at once, then the forum\'s, once each',
        () async {
      final s = suggester(people: [person('ann'), person('bob')]);
      answers[''] = [person('bob'), person('cat')];
      s.update(typed('@'));
      expect(names(s), ['ann', 'bob'], reason: 'before the forum answers');
      await settle();
      expect(names(s), ['ann', 'bob', 'cat']);
      expect(asked, ['']);

      s.update(typed('x'));
      expect(names(s), isEmpty, reason: 'no @ being typed');
      s.update(typed('x @'));
      expect(asked, [''], reason: 'the answer is kept');
      expect(names(s), ['ann', 'bob', 'cat']);
    });

    test('the writer is never offered, and at most five are', () async {
      final s = suggester(
          people: [for (final n in ['me', 'a1', 'a2', 'a3', 'a4', 'a5', 'a6']) person(n)],
          self: 'Me');
      s.update(typed('@'));
      expect(names(s), ['a1', 'a2', 'a3', 'a4', 'a5']);
    });

    test('one letter narrows what is known without asking', () async {
      final s = suggester(people: [person('ann', name: 'Zed Ann'), person('bob')]);
      answers[''] = [person('amy')];
      s.update(typed('@'));
      await settle();
      s.update(typed('@a'));
      expect(names(s), ['ann', 'amy']);
      s.update(typed('@z'));
      expect(names(s), ['ann'], reason: 'by name too');
      await settle();
      expect(asked, ['']);
    });

    test('from the second letter the forum\'s matches join them', () async {
      final s = suggester(people: [person('sam')]);
      answers['sa'] = [person('sam'), person('sara')];
      s.update(typed('@sa'));
      expect(names(s), ['sam']);
      await settle();
      expect(names(s), ['sam', 'sara']);
      expect(asked, ['sa'],
          reason: '@ alone was never on screen, so not asked for');
    });

    test('an answer for what is no longer typed is not shown', () async {
      final s = suggester();
      answers['sa'] = [person('sara')];
      s.update(typed('@sa'));
      // The term changes before the debounce fires.
      s.update(typed('@sa '));
      await settle();
      expect(names(s), isEmpty);
    });

    test('forgetting the answers asks again', () async {
      final s = suggester();
      s.update(typed('@'));
      await settle();
      s.forgetAnswers();
      s.update(typed('x'));
      s.update(typed('@'));
      await settle();
      expect(asked, ['', '']);
    });
  });

  test('the topic\'s people: the replied-to author first, then the newest',
      () {
    FCPost post(int n, String user, {String id = '1', String? action}) => FCPost(
          id: 'p$n',
          title: '',
          content: '',
          topicId: 't',
          actionCode: action,
          authorId: id,
          authorName: user,
          authorDisplayName: '$user!',
          postNumber: n,
        );
    final posts = [
      post(1, 'ann'),
      post(2, 'system', id: '-1'),
      post(3, 'bob'),
      post(4, 'ann'),
      post(5, 'cat'),
      post(6, 'mod', action: 'closed.enabled'),
    ];
    final people = topicMentionPeople(posts, replyTo: posts[2]);
    expect([for (final p in people) p.username], ['bob', 'cat', 'ann']);
    expect(people.first.name, 'bob!');
  });
}
