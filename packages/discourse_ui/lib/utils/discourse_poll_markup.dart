/// A poll as the composer writes it into a post: Discourse's `[poll]`
/// block, which the poll plugin turns into the poll when the post is
/// cooked. The builder (`PollBuilderPage`) edits one of these, and the
/// composer finds the ones already in the text ([findIn]) to offer them
/// again.
///
/// What it writes is what the web's poll builder writes
/// (poll-ui-builder.gjs `pollOutput`):
///
/// ```
/// [poll type=regular results=always public=true chartType=bar]
/// # Title
/// * One
/// * Two
/// [/poll]
/// ```
library;

/// The kinds of poll the builder makes. Discourse also has ranked choice;
/// a poll of a kind not listed here can be removed but not edited.
enum DiscoursePollType { regular, multiple, number }

/// Who sees the results, and when (`results=`).
enum DiscoursePollResults {
  always('always'),
  onVote('on_vote'),
  onClose('on_close'),
  staffOnly('staff_only');

  const DiscoursePollResults(this.value);
  final String value;

  static DiscoursePollResults parse(String? value) => values.firstWhere(
      (r) => r.value == value,
      orElse: () => DiscoursePollResults.always);
}

enum DiscoursePollChart { bar, pie }

class DiscoursePoll {
  const DiscoursePoll({
    this.name,
    this.type = DiscoursePollType.regular,
    this.typeName,
    this.title = '',
    this.options = const [],
    this.min,
    this.max,
    this.step,
    this.results = DiscoursePollResults.always,
    this.isPublic = true,
    this.close,
    this.chart = DiscoursePollChart.bar,
    this.extra = const {},
  });

  /// Tells polls in one post apart (`name=`); Discourse's own default,
  /// `poll`, is not written.
  final String? name;
  final DiscoursePollType type;

  /// The `type=` it was written with when that is not one of [type]'s
  /// (`ranked_choice`): the builder cannot edit it.
  final String? typeName;
  final String title;
  final List<String> options;

  /// Multiple choice: how many options a voter picks. Number rating: the
  /// lowest and highest number, and the [step] between them.
  final int? min;
  final int? max;
  final int? step;
  final DiscoursePollResults results;

  /// Whether voters are shown (`public=true`; without it they are not).
  final bool isPublic;

  /// When voting closes by itself (`close=`).
  final DateTime? close;
  final DiscoursePollChart chart;

  /// Attributes the builder does not offer (`groups=`, `dynamic=`,
  /// `status=`), kept as they were when a poll is edited.
  final Map<String, String> extra;

  /// Whether the builder can edit it.
  bool get isEditable => typeName == null;

  /// The name Discourse knows it by: `poll` unless it has another.
  String get key => name ?? 'poll';

  DiscoursePoll copyWith({String? name}) => DiscoursePoll(
        name: name ?? this.name,
        type: type,
        typeName: typeName,
        title: title,
        options: options,
        min: min,
        max: max,
        step: step,
        results: results,
        isPublic: isPublic,
        close: close,
        chart: chart,
        extra: extra,
      );

  /// The block, as the web's builder writes it.
  String toMarkup() {
    final attrs = [
      if (name != null && name != 'poll') 'name=$name',
      'type=${typeName ?? type.name}',
      'results=${results.value}',
      if (type != DiscoursePollType.regular && min != null) 'min=$min',
      if (type != DiscoursePollType.regular && max != null) 'max=$max',
      if (type == DiscoursePollType.number) 'step=${step ?? 1}',
      'public=$isPublic',
      if (type != DiscoursePollType.number) 'chartType=${chart.name}',
      for (final e in extra.entries) '${e.key}=${e.value}',
      if (close != null) 'close=${_iso(close!)}',
    ];
    return [
      '[poll ${attrs.join(' ')}]',
      if (title.trim().isNotEmpty) '# ${title.trim()}',
      if (type != DiscoursePollType.number)
        for (final o in options)
          if (o.trim().isNotEmpty) '* ${o.trim()}',
      '[/poll]',
    ].join('\n');
  }

  /// To the second, in UTC, as the web's `toISOString()` (less its
  /// milliseconds, which a picked time does not have).
  static String _iso(DateTime t) {
    final s = t.toUtc().toIso8601String();
    final dot = s.indexOf('.');
    return dot < 0 ? s : '${s.substring(0, dot)}Z';
  }

  static final RegExp _block = RegExp(
      r'\[poll((?:\s+[\w-]+=(?:"[^"]*"|[^\s\]]*))*)\s*\]([\s\S]*?)\[/poll\]',
      caseSensitive: false);
  static final RegExp _attr = RegExp(r'([\w-]+)=(?:"([^"]*)"|([^\s\]]*))');
  static final RegExp _option = RegExp(r'^\s*(?:[*+-]|\d+[.)])\s+(.*\S)\s*$');
  static final RegExp _heading = RegExp(r'^\s*#{1,6}\s+(.*\S)\s*$');

  /// Every poll in [text], with where its block starts and ends.
  static List<({int start, int end, DiscoursePoll poll})> findIn(String text) => [
        for (final m in _block.allMatches(text))
          (start: m.start, end: m.end, poll: _parse(m.group(1)!, m.group(2)!)),
      ];

  static DiscoursePoll _parse(String attributes, String body) {
    final attrs = <String, String>{
      for (final a in _attr.allMatches(attributes))
        a.group(1)!: a.group(2) ?? a.group(3) ?? '',
    };
    String? title;
    final options = <String>[];
    for (final line in body.split('\n')) {
      final option = _option.firstMatch(line);
      if (option != null) {
        options.add(option.group(1)!);
        continue;
      }
      title ??= _heading.firstMatch(line)?.group(1);
    }
    final typeName = attrs.remove('type') ?? 'regular';
    final type = DiscoursePollType.values
        .where((t) => t.name == typeName)
        .firstOrNull;
    final chart = attrs.remove('chartType');
    final public = attrs.remove('public');
    return DiscoursePoll(
      name: attrs.remove('name'),
      type: type ?? DiscoursePollType.regular,
      typeName: type == null ? typeName : null,
      title: title ?? '',
      options: options,
      min: int.tryParse(attrs.remove('min') ?? ''),
      max: int.tryParse(attrs.remove('max') ?? ''),
      step: int.tryParse(attrs.remove('step') ?? ''),
      results: DiscoursePollResults.parse(attrs.remove('results')),
      // Discourse's own default: voters are not shown.
      isPublic: public == 'true',
      close: DateTime.tryParse(attrs.remove('close') ?? '')?.toLocal(),
      chart: chart == 'pie' ? DiscoursePollChart.pie : DiscoursePollChart.bar,
      extra: attrs,
    );
  }

  /// A name for one more poll in [text]: Discourse needs each poll in a
  /// post to have its own, and the first is `poll`. Null when [text] has
  /// none yet.
  static String? nameForAnother(String text) {
    final taken = {for (final p in findIn(text)) p.poll.key};
    if (taken.isEmpty) return null;
    for (var n = taken.length + 1;; n++) {
      if (!taken.contains('poll$n')) return 'poll$n';
    }
  }
}
