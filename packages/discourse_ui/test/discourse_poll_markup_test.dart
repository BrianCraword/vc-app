import 'package:discourse_ui/utils/discourse_poll_markup.dart';
import 'package:flutter_test/flutter_test.dart';

/// The `[poll]` block the composer writes is the web builder's, and the
/// polls already in a post can be read back to edit.
void main() {
  test('a single-choice poll, as the web writes it', () {
    const poll = DiscoursePoll(
      title: 'Lunch?',
      options: ['Pizza', ' Soup ', ''],
    );
    expect(poll.toMarkup(), '''
[poll type=regular results=always public=true chartType=bar]
# Lunch?
* Pizza
* Soup
[/poll]''');
  });

  test('multiple choice and number rating carry their limits', () {
    expect(
      const DiscoursePoll(
        name: 'poll2',
        type: DiscoursePollType.multiple,
        options: ['A', 'B', 'C'],
        min: 1,
        max: 2,
        results: DiscoursePollResults.onVote,
        isPublic: false,
        chart: DiscoursePollChart.pie,
      ).toMarkup(),
      '[poll name=poll2 type=multiple results=on_vote min=1 max=2 '
      'public=false chartType=pie]\n* A\n* B\n* C\n[/poll]',
    );
    expect(
      DiscoursePoll(
        type: DiscoursePollType.number,
        options: const ['ignored'],
        min: 1,
        max: 10,
        step: 2,
        results: DiscoursePollResults.onClose,
        close: DateTime.utc(2026, 11, 2, 18, 30, 0, 123),
      ).toMarkup(),
      '[poll type=number results=on_close min=1 max=10 step=2 public=true '
      'close=2026-11-02T18:30:00Z]\n[/poll]',
      reason: 'no chart and no options for a number rating',
    );
  });

  test('polls in a post are found, and read back', () {
    const text = 'Before\n'
        '[poll type=multiple results=staff_only min=2 max=3 public=true chartType=pie groups=team status=closed]\n'
        '## Which ones?\n'
        '* One\n'
        '- Two\n'
        '1. Three\n'
        '[/poll]\n'
        'Between\n'
        '[poll name=second]\n* Yes\n* No\n[/poll]\n';
    final found = DiscoursePoll.findIn(text);
    expect(found, hasLength(2));
    final first = found.first.poll;
    expect(text.substring(found.first.start, found.first.end),
        startsWith('[poll type=multiple'));
    expect(text.substring(found.first.start, found.first.end), endsWith('[/poll]'));
    expect(first.type, DiscoursePollType.multiple);
    expect(first.title, 'Which ones?');
    expect(first.options, ['One', 'Two', 'Three']);
    expect((first.min, first.max), (2, 3));
    expect(first.results, DiscoursePollResults.staffOnly);
    expect(first.isPublic, isTrue);
    expect(first.chart, DiscoursePollChart.pie);
    expect(first.extra, {'groups': 'team', 'status': 'closed'},
        reason: 'what the builder does not offer is kept');
    expect(first.toMarkup(), contains('groups=team status=closed'));

    final second = found.last.poll;
    expect(second.key, 'second');
    expect(second.isPublic, isFalse, reason: 'Discourse\'s default');
    expect(second.results, DiscoursePollResults.always);
  });

  test('a ranked-choice poll can be found but not edited', () {
    final poll = DiscoursePoll.findIn(
            '[poll type=ranked_choice]\n* A\n* B\n[/poll]')
        .single
        .poll;
    expect(poll.isEditable, isFalse);
    expect(poll.toMarkup(), startsWith('[poll type=ranked_choice '));
  });

  test('each poll in a post gets a name of its own', () {
    expect(DiscoursePoll.nameForAnother('no polls'), isNull);
    expect(DiscoursePoll.nameForAnother('[poll]\n* A\n[/poll]'), 'poll2');
    expect(
        DiscoursePoll.nameForAnother(
            '[poll]\n* A\n[/poll]\n[poll name=poll2]\n* B\n[/poll]'),
        'poll3');
  });
}
