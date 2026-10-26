/// What is being discussed in a category: the most recently posted in of
/// its featured topics, which `/categories.json` carries per category with
/// `include_topics=true` (or when the forum's categories page shows
/// topics). The Categories view's card shows it under the description.
///
/// Discourse picks a category's featured topics every few minutes, pinned
/// first, and their order is not by date, so the latest is taken by
/// [lastPostedAt].
class DiscourseCategoryLatestTopic {
  const DiscourseCategoryLatestTopic({
    required this.id,
    required this.title,
    this.slug,
    this.lastPostedAt,
    this.highestPostNumber = 1,
  });

  final int id;

  /// The raw title (`fancy_title` is HTML-escaped).
  final String title;
  final String? slug;
  final DateTime? lastPostedAt;

  /// Where its last post is, to open it there.
  final int highestPostNumber;

  /// The most recently posted in of a category's `topics`; null when it
  /// has none.
  static DiscourseCategoryLatestTopic? latestOf(Object? topics) {
    if (topics is! List) return null;
    DiscourseCategoryLatestTopic? latest;
    for (final t in topics.whereType<Map>()) {
      final id = t['id'];
      final title = t['title']?.toString().trim() ?? '';
      if (id is! int || title.isEmpty) continue;
      final at = DateTime.tryParse(
          (t['last_posted_at'] ?? t['bumped_at'] ?? '').toString());
      final topic = DiscourseCategoryLatestTopic(
        id: id,
        title: title,
        slug: t['slug']?.toString(),
        lastPostedAt: at,
        highestPostNumber: (t['highest_post_number'] as num?)?.toInt() ?? 1,
      );
      final best = latest?.lastPostedAt;
      if (latest == null || (at != null && (best == null || at.isAfter(best)))) {
        latest = topic;
      }
    }
    return latest;
  }
}
