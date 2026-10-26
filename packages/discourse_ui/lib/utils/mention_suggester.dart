import 'dart:async';

import 'package:discourse_core/discourse_core.dart'
    show DiscourseMentionCandidate;
import 'package:flutter/widgets.dart';
import 'package:forumcopilot_sdk/models/entities/fc_post.dart';

/// Asks the forum who an `@` being typed could name: the term after the
/// `@`, empty for `@` alone.
typedef MentionSearch = Future<List<DiscourseMentionCandidate>> Function(
    String term);

/// A topic's people from the posts its page has loaded, for `@`: the
/// author of [replyTo] (the post being answered) first, then the newest
/// posters, each once. Discourse's own accounts (system, discobot: ids
/// below 1) are left out, as nobody means to mention them, and so are the
/// staff whose only part was an action ("closed the topic"): the forum
/// counts regular posts only.
List<DiscourseMentionCandidate> topicMentionPeople(List<FCPost> posts,
    {FCPost? replyTo}) {
  final newestFirst = [...posts]
    ..sort((a, b) => (b.postNumber ?? 0).compareTo(a.postNumber ?? 0));
  final seen = <String>{};
  return [
    for (final p in [if (replyTo != null) replyTo, ...newestFirst])
      if (p.authorName.isNotEmpty &&
          p.actionCode == null &&
          (int.tryParse(p.authorId) ?? 1) > 0 &&
          seen.add(p.authorName.toLowerCase()))
        (
          username: p.authorName,
          name: p.authorDisplayName,
          avatarUrl: p.authorIconUrl,
          isGroup: false,
        ),
  ];
}

/// What the composer offers above its toolbar while an `@name` is being
/// typed, as the web composer's mention autocomplete does, a tap away.
///
/// `@` alone offers the topic's people at once: [people] (the posters the
/// topic page has loaded, newest first) and then the forum's answer for an
/// empty term, which a reply scopes to its topic. From the second letter,
/// the forum's matches join them, a moment after typing stops. Each answer
/// is kept, so typing back and forth asks once per term. The writer is
/// never offered ([selfUsername]); at most [limit] are.
class MentionSuggester extends ChangeNotifier {
  MentionSuggester({
    required MentionSearch search,
    List<DiscourseMentionCandidate> people = const [],
    String? selfUsername,
    this.limit = 5,
    this.debounce = const Duration(milliseconds: 250),
  })  : _search = search,
        _people = people,
        _self = selfUsername?.toLowerCase();

  final MentionSearch _search;
  final int limit;
  final Duration debounce;
  List<DiscourseMentionCandidate> _people;
  final String? _self;

  final Map<String, List<DiscourseMentionCandidate>> _answers = {};
  final Set<String> _asked = {};
  Timer? _timer;
  String? _typing;
  bool _disposed = false;

  List<DiscourseMentionCandidate> _suggestions = const [];
  List<DiscourseMentionCandidate> get suggestions => _suggestions;

  /// The `@` and what follows it, just before a collapsed cursor: after the
  /// start of the text, a space or an opening bracket, so an email address
  /// is not a mention. Discourse usernames are letters, digits, `_`, `.`
  /// and `-`, in any script where the forum allows unicode usernames.
  static final RegExp _typed = RegExp(
      r'(?:^|[\s(\[])@([\p{L}\p{M}\p{N}_.\-]{0,30})$',
      unicode: true);

  /// The `@name` typed just before the cursor in [value]: where its `@` is,
  /// and the name so far (empty just after the `@`). Null when the cursor
  /// is not at the end of one.
  static ({int start, String query})? mentionAt(TextEditingValue value) {
    final sel = value.selection;
    if (!sel.isValid || !sel.isCollapsed) return null;
    final cursor = sel.baseOffset;
    if (cursor < 0 || cursor > value.text.length) return null;
    final m = _typed.firstMatch(value.text.substring(0, cursor));
    if (m == null) return null;
    final query = m.group(1)!;
    return (start: cursor - query.length - 1, query: query);
  }

  /// [candidate]'s mention in place of the `@name` being typed in [value],
  /// with a space after it and the cursor past the space; null when no
  /// `@name` is being typed.
  static TextEditingValue? complete(
      TextEditingValue value, DiscourseMentionCandidate candidate) {
    final typing = mentionAt(value);
    if (typing == null) return null;
    final mention = '@${candidate.username} ';
    return TextEditingValue(
      text: value.text
          .replaceRange(typing.start, value.selection.baseOffset, mention),
      selection:
          TextSelection.collapsed(offset: typing.start + mention.length),
    );
  }

  /// The topic page's people changed (more posts loaded).
  set people(List<DiscourseMentionCandidate> people) => _people = people;

  /// Forgets the forum's answers: where they were scoped has changed.
  void forgetAnswers() {
    _answers.clear();
    _asked.clear();
  }

  /// Follows the text: what to offer for the `@name` at its cursor, if any.
  void update(TextEditingValue value) {
    _timer?.cancel();
    final query = mentionAt(value)?.query;
    _typing = query;
    if (query == null) return _show(const []);
    _show(_offer(query));
    if (_asked.contains(query)) return;
    if (query.isEmpty) {
      _ask(query);
    } else if (query.length >= 2) {
      _timer = Timer(debounce, () => _ask(query));
    }
  }

  Future<void> _ask(String query) async {
    _asked.add(query);
    final List<DiscourseMentionCandidate> found;
    try {
      found = await _search(query);
    } catch (_) {
      // A convenience: the @ button still searches. Asked again next time.
      _asked.remove(query);
      return;
    }
    if (_disposed) return;
    _answers[query] = found;
    if (_typing == query) _show(_offer(query));
  }

  /// The topic's people whose username or name starts with [query], then
  /// the forum's answers for `@` alone and for [query], each once.
  List<DiscourseMentionCandidate> _offer(String query) {
    final q = query.toLowerCase();
    bool starts(DiscourseMentionCandidate c) =>
        q.isEmpty ||
        c.username.toLowerCase().startsWith(q) ||
        (c.name?.toLowerCase().startsWith(q) ?? false);
    final seen = <String>{if (_self != null) _self};
    final out = <DiscourseMentionCandidate>[];
    for (final c in [
      ..._people.where(starts),
      ...?_answers['']?.where(starts),
      if (q.isNotEmpty) ...?_answers[query],
    ]) {
      if (out.length == limit) break;
      if (seen.add(c.username.toLowerCase())) out.add(c);
    }
    return out;
  }

  void _show(List<DiscourseMentionCandidate> next) {
    if (_same(next, _suggestions)) return;
    _suggestions = next;
    notifyListeners();
  }

  static bool _same(
      List<DiscourseMentionCandidate> a, List<DiscourseMentionCandidate> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}
