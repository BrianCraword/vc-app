import 'package:discourse_core/discourse_core.dart'
    show
        DiscourseBookmarkProxy,
        DiscourseLink,
        DiscourseTopicProxy,
        DiscourseTopicSlugs,
        DiscourseTopicTracking;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:forumcopilot_sdk/context/site_context.dart';
import 'package:forumcopilot_sdk/models/entities/fc_notification_level.dart';
import 'package:forumcopilot_sdk/models/entities/fc_topic.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../l10n/kit_strings.dart';
import '../../utils/emoji_shortcodes.dart';
import '../../utils/error_message.dart';
import '../../utils/snackbar_helper.dart';
import '../../utils/url_utils.dart';
import 'category_masthead.dart';
import 'notification_level_sheet.dart';
import 'sheet_title.dart';

/// What a reader can do with a topic from its row in a list, without
/// opening it: swipe a new or unread row to dismiss it, or long-press any
/// row for the sheet ([showSheet]). From the Flarum app's discussion rows;
/// the actions are the web's for one topic.
abstract final class TopicActions {
  /// The forum, for a test.
  @visibleForTesting
  static DiscourseTopicProxy Function(SiteContext)? debugTopicProxy;
  @visibleForTesting
  static DiscourseBookmarkProxy Function(SiteContext)? debugBookmarkProxy;

  static DiscourseTopicProxy _topics(SiteContext site) =>
      debugTopicProxy?.call(site) ?? DiscourseTopicProxy(site);

  static DiscourseBookmarkProxy _bookmarks(SiteContext site) =>
      debugBookmarkProxy?.call(site) ?? DiscourseBookmarkProxy(site);

  /// Dismisses [topic] as the web's Dismiss does for chosen topics: it is
  /// no longer new, and its replies are read. The row stays where it is
  /// and follows the tracking store; the forum's reason shows if it says no.
  static Future<void> dismiss(
      BuildContext context, SiteContext site, FCTopic topic) async {
    final result = await _topics(site).markTopicReadAsync([topic.id]);
    if (!result.result && context.mounted) {
      SnackbarHelper.showError(
          context, describeError(result.resultText, context: context));
    }
  }

  /// The long-press sheet: Dismiss (a new or unread topic), its
  /// notification level, its bookmark, Share and Copy link. A guest gets
  /// the last two.
  static Future<void> showSheet(
    BuildContext context,
    SiteContext site,
    FCTopic topic, {
    required bool canDismiss,
  }) {
    final signedIn = site.isLoggedIn;
    final state = DiscourseTopicTracking.forSite(site).stateOf(topic.id);
    final level = FCNotificationLevel.fromInt(state?.notificationLevel);
    final bookmarked = state?.bookmarked ?? false;
    final base = site.site.url;
    final link = DiscourseLink.webUrl(base,
        topicId: topic.id, slug: DiscourseTopicSlugs.of(base, topic.id));

    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheet) {
        final l10n = AppLocalizations.of(sheet)!;
        // The sheet goes first; what follows happens on the list.
        void then(Future<void> Function() action) {
          Navigator.pop(sheet);
          action();
        }

        return SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SheetTitle(withEmojiShortcodes(topic.title)),
                if (signedIn && canDismiss)
                  ListTile(
                    leading: const Icon(Icons.done),
                    title: Text(l10n.dismiss),
                    onTap: () => then(() => dismiss(context, site, topic)),
                  ),
                if (signedIn) ...[
                  ListTile(
                    leading: Icon(CategoryMasthead.levelIcon(level)),
                    title: Text(l10n.kit.notifications),
                    subtitle: Text(CategoryMasthead.levelLabel(l10n, level)),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => then(() => NotificationLevelSheet.showForTopic(
                          context: context,
                          topicId: topic.id,
                          currentLevel: level,
                        )),
                  ),
                  ListTile(
                    leading: Icon(bookmarked
                        ? Icons.bookmark_remove_outlined
                        : Icons.bookmark_add_outlined),
                    title: Text(bookmarked
                        ? l10n.deleteTopicBookmarks
                        : l10n.bookmarkTopic),
                    onTap: () => then(() => bookmarked
                        ? _deleteBookmarks(context, site, topic)
                        : _bookmark(context, site, topic)),
                  ),
                ],
                Builder(
                  builder: (tile) => ListTile(
                    leading: const Icon(Icons.share_outlined),
                    title: Text(l10n.kit.share),
                    onTap: () {
                      // Where an iPad points the share sheet from: read
                      // before this sheet goes.
                      final box = tile.findRenderObject();
                      final origin = box is RenderBox && box.hasSize
                          ? box.localToGlobal(Offset.zero) & box.size
                          : null;
                      then(() => UrlUtils.shareUrl(link,
                          title: topic.title, sharePositionOrigin: origin));
                    },
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.link),
                  title: Text(l10n.copyLink),
                  onTap: () => then(() async {
                    await Clipboard.setData(ClipboardData(text: link));
                    if (context.mounted) {
                      SnackbarHelper.showInfo(context, l10n.linkCopied);
                    }
                  }),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  static Future<void> _bookmark(
      BuildContext context, SiteContext site, FCTopic topic) async {
    final l10n = AppLocalizations.of(context)!;
    final result = await _bookmarks(site).addTopicBookmarkAsync(topic.id);
    if (!context.mounted) return;
    result.result
        ? SnackbarHelper.showInfo(context, l10n.topicBookmarked)
        : SnackbarHelper.showError(
            context, describeError(result.resultText, context: context));
  }

  /// The web asks first: reminders and labels go with the bookmarks.
  static Future<void> _deleteBookmarks(
      BuildContext context, SiteContext site, FCTopic topic) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        content: Text(l10n.deleteTopicBookmarksQuestion),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: Text(l10n.kit.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: Text(l10n.kit.delete),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final result = await _bookmarks(site).deleteTopicBookmarksAsync(topic.id);
    if (!context.mounted) return;
    result.result
        ? SnackbarHelper.showInfo(context, l10n.topicBookmarksDeleted)
        : SnackbarHelper.showError(
            context, describeError(result.resultText, context: context));
  }
}
