import 'package:discourse_core/discourse_core.dart'
    show DiscourseCategoryLatestTopic, DiscourseSiteCapabilities;
import 'package:flutter/material.dart';
import 'package:forumcopilot_sdk/context/site_context.dart';
import 'package:forumcopilot_sdk/models/entities/fc_forum.dart';
import 'package:intl/intl.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../utils/discourse_color.dart';
import '../../utils/emoji_shortcodes.dart';
import '../../utils/forum_navigation.dart';
import '../../utils/time_utils.dart';
import '../../services/notification_route.dart'
    show DiscourseNotificationRoute;
import '../lists/posts_list.dart' show PostsListMode;
import '../post_page.dart';
import '../widgets/category_badge.dart' show categoryMarkColor;
import '../widgets/category_read_counts.dart';
import '../widgets/category_tile_mark.dart';

/// "15 new this week", or the category's topic count when the forum has not
/// said how its week went; null when there is nothing to say.
String? categoryActivityLine(
    BuildContext context, SiteContext siteContext, FCForum forum) {
  final l10n = AppLocalizations.of(context)!;
  final id = int.tryParse(forum.id);
  final week = id == null
      ? null
      : DiscourseSiteCapabilities.forSite(siteContext.site.pluginUrl)
          .topicsThisWeek[id];
  if (week != null && week > 0) return l10n.categoryNewThisWeek(week);
  if (forum.topicCount <= 0) return null;
  final compact =
      NumberFormat.compact(locale: Localizations.localeOf(context).toString());
  return l10n.countTopics(forum.topicCount, compact.format(forum.topicCount));
}

/// A category in the forum's Categories view: its own mark and name, how
/// active it is this week, two lines of description, its latest topic, and
/// its subcategories as small chips. A band of its colour runs down the left edge, as on
/// Discourse's category badges; a bell marks one you watch or track.
class CategoryCard extends StatelessWidget {
  const CategoryCard({
    super.key,
    required this.siteContext,
    required this.forum,
    this.showSubcategories = true,
    this.margin = const EdgeInsets.fromLTRB(16, 4, 16, 4),
  });

  final SiteContext siteContext;
  final FCForum forum;
  final bool showSubcategories;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final style = DiscourseSiteCapabilities.forSite(siteContext.site.pluginUrl)
        .categoryStyleFor(forum.id);
    final color = categoryMarkColor(
      parseDiscourseHex(style?.colorHex ?? forum.color ?? '') ?? scheme.outline,
      scheme.surface,
    );
    final description = (forum.description?.trim().isNotEmpty ?? false)
        ? forum.description!.trim()
        : style?.description;
    final activity = categoryActivityLine(context, siteContext, forum);
    final subs = showSubcategories ? forum.childForums : const <FCForum>[];
    final latest = DiscourseSiteCapabilities.forSite(siteContext.site.pluginUrl)
        .latestTopics[int.tryParse(forum.id)];

    return Padding(
      padding: margin,
      child: Material(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => pushForumOrLinkForum(context, forum, siteContext),
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border(left: BorderSide(color: color, width: 4)),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CategoryTileMark(
                        style: style,
                        size: 24,
                        fallbackColorHex: forum.color,
                        fallbackLogoUrl: forum.logoUrl,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          forum.name,
                          style: text.titleMedium,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (forum.isSubscribed) ...[
                        const SizedBox(width: 8),
                        Icon(Icons.notifications_active_outlined,
                            size: 16, color: scheme.onSurfaceVariant),
                      ],
                      if (activity != null) ...[
                        const SizedBox(width: 8),
                        Text(
                          activity,
                          style: text.bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ],
                  ),
                  if (description != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodyMedium
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                  if (latest != null)
                    CategoryLatestTopicLine(
                      siteContext: siteContext,
                      topic: latest,
                      forumId: forum.id,
                    ),
                  CategoryReadCounts(
                    siteContext: siteContext,
                    categoryId: forum.id,
                    padding: const EdgeInsets.only(top: 6),
                  ),
                  if (subs.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      children: [
                        for (final sub in subs)
                          SubcategoryChip(siteContext: siteContext, forum: sub),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// What is being discussed in a category, under its description: its
/// latest topic's title and when it was last posted in. A tap opens the
/// topic at its last post, as the Flarum app's tag cards do.
class CategoryLatestTopicLine extends StatelessWidget {
  const CategoryLatestTopicLine({
    super.key,
    required this.siteContext,
    required this.topic,
    required this.forumId,
  });

  final SiteContext siteContext;
  final DiscourseCategoryLatestTopic topic;
  final String forumId;

  /// The topic, opened at its last post.
  static PostPage pageFor(SiteContext siteContext,
      DiscourseCategoryLatestTopic topic, String forumId) {
    final last = topic.highestPostNumber < 1 ? 1 : topic.highestPostNumber;
    return PostPage(
      siteContext: siteContext,
      topicId: '${topic.id}',
      title: topic.title,
      mode: PostsListMode.goto_page,
      gotoPage: (last - 1) ~/ DiscourseNotificationRoute.postsPerPage + 1,
      gotoPostNumber: last,
      forumId: forumId,
    );
  }

  void _open(BuildContext context) => Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => pageFor(siteContext, topic, forumId)));

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final title = withEmojiShortcodes(topic.title);
    final at = topic.lastPostedAt;
    final time = at == null ? '' : formatSmartDateTime(at.toLocal(), context);
    // Its own button, not more words in the card's.
    return Semantics(
      container: true,
      button: true,
      label: AppLocalizations.of(context)!.categoryLatestTopic(title, time),
      excludeSemantics: true,
      child: InkWell(
        onTap: () => _open(context),
        borderRadius: BorderRadius.circular(8),
        child: ConstrainedBox(
          // A finger's room, so a tap meant for it does not open the card.
          constraints: const BoxConstraints(minHeight: 40),
          child: Row(
            children: [
              Icon(Icons.chat_bubble_outline,
                  size: 16, color: scheme.onSurfaceVariant),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodyMedium?.copyWith(color: scheme.onSurface),
                ),
              ),
              if (time.isNotEmpty) ...[
                const SizedBox(width: 8),
                Text(time,
                    style: text.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A subcategory as a small chip — its colour and name — that opens it.
/// 32dp tall to tap, so a tap meant for it does not open the card it
/// sits on.
class SubcategoryChip extends StatelessWidget {
  const SubcategoryChip({
    super.key,
    required this.siteContext,
    required this.forum,
    this.outlined = false,
  });

  final SiteContext siteContext;
  final FCForum forum;

  /// Drawn with an outline on the page rather than filled on a card.
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final style = DiscourseSiteCapabilities.forSite(siteContext.site.pluginUrl)
        .categoryStyleFor(forum.id);
    final color = categoryMarkColor(
      parseDiscourseHex(style?.colorHex ?? forum.color ?? '') ?? scheme.outline,
      scheme.surface,
    );
    final radius = BorderRadius.circular(8);
    return InkWell(
      borderRadius: radius,
      onTap: () => pushForumOrLinkForum(context, forum, siteContext),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: outlined ? null : scheme.surfaceContainerHigh,
            border: outlined ? Border.all(color: scheme.outlineVariant) : null,
            borderRadius: radius,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  forum.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.labelMedium,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A parent category whose forum shows its subcategories as boxes (Asana
/// puts every category under one): its [CategorySectionHeading] above its
/// subcategories' own cards, which hang from a rail of the parent's colour
/// so the top-level category after the group does not read as one of them
/// (Python.org's Typing follows its Packaging group).
class CategoryGroup extends StatelessWidget {
  const CategoryGroup({
    super.key,
    required this.siteContext,
    required this.forum,
  });

  final SiteContext siteContext;
  final FCForum forum;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = DiscourseSiteCapabilities.forSite(siteContext.site.pluginUrl)
        .categoryStyleFor(forum.id);
    final rail = categoryMarkColor(
      parseDiscourseHex(style?.colorHex ?? forum.color ?? '') ??
          scheme.outlineVariant,
      scheme.surface,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CategorySectionHeading(siteContext: siteContext, forum: forum),
        // The rail runs down from the middle of the heading's 20dp mark.
        Padding(
          padding: const EdgeInsets.fromLTRB(25, 0, 0, 12),
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border(left: BorderSide(color: rail, width: 2)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final child in forum.childForums)
                  CategoryCard(
                    siteContext: siteContext,
                    forum: child,
                    margin: const EdgeInsets.fromLTRB(12, 4, 16, 4),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// The heading of a [CategoryGroup]: opens the parent.
class CategorySectionHeading extends StatelessWidget {
  const CategorySectionHeading({
    super.key,
    required this.siteContext,
    required this.forum,
  });

  final SiteContext siteContext;
  final FCForum forum;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final activity = categoryActivityLine(context, siteContext, forum);
    return InkWell(
      onTap: () => pushForumOrLinkForum(context, forum, siteContext),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
        child: Row(
          children: [
            CategoryTileMark.forId(siteContext, forum.id,
                size: 20,
                fallbackColorHex: forum.color,
                fallbackLogoUrl: forum.logoUrl),
            const SizedBox(width: 10),
            Expanded(
              child: Semantics(
                header: true,
                child: Text(forum.name,
                    style: text.titleSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ),
            ),
            if (activity != null)
              Text(activity,
                  style:
                      text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
            Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}
