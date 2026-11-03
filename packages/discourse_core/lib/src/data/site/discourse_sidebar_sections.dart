import 'package:flutter/foundation.dart';

/// One link in a forum's sidebar, as Discourse serves it.
///
/// Shape is `SidebarUrlSerializer`: id, name, value, icon, external, segment.
@immutable
class DiscourseSidebarLink {
  const DiscourseSidebarLink({
    required this.id,
    required this.name,
    required this.value,
    this.icon,
    this.external = false,
    this.secondary = false,
  });

  final int id;

  /// What the forum calls it. Already localised by the server where the
  /// forum has translations, so it is shown as given.
  final String name;

  /// Where it points: a forum path (`/feed`), or an absolute URL when
  /// [external].
  final String value;

  /// A Font Awesome name, which `materialIconForDiscourseIcon` maps.
  final String? icon;

  /// Leaves the forum. Discourse decides this itself.
  final bool external;

  /// Discourse's `segment`: primary links sit above, secondary below.
  final bool secondary;

  static DiscourseSidebarLink? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = (raw['id'] as num?)?.toInt();
    final name = raw['name']?.toString().trim();
    final value = raw['value']?.toString().trim();
    if (id == null) return null;
    if (name == null || name.isEmpty) return null;
    if (value == null || value.isEmpty) return null;
    final icon = raw['icon']?.toString().trim();
    return DiscourseSidebarLink(
      id: id,
      name: name,
      value: value,
      icon: (icon == null || icon.isEmpty) ? null : icon,
      external: raw['external'] == true,
      secondary: raw['segment']?.toString() == 'secondary',
    );
  }
}

/// A section of a forum's sidebar.
@immutable
class DiscourseSidebarSection {
  const DiscourseSidebarSection({
    required this.id,
    required this.title,
    required this.slug,
    required this.sectionType,
    required this.links,
  });

  final int id;
  final String title;
  final String slug;

  /// Discourse's `section_type`: `community` for the one every forum has,
  /// null for a section someone created.
  final String? sectionType;

  final List<DiscourseSidebarLink> links;

  bool get isCommunity => sectionType == 'community';

  List<DiscourseSidebarLink> get primaryLinks =>
      links.where((l) => !l.secondary).toList(growable: false);
  List<DiscourseSidebarLink> get secondaryLinks =>
      links.where((l) => l.secondary).toList(growable: false);

  static DiscourseSidebarSection? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = (raw['id'] as num?)?.toInt();
    final title = raw['title']?.toString().trim();
    if (id == null || title == null || title.isEmpty) return null;
    final links = (raw['links'] as List?)
            ?.map(DiscourseSidebarLink.fromJson)
            .whereType<DiscourseSidebarLink>()
            .toList(growable: false) ??
        const <DiscourseSidebarLink>[];
    return DiscourseSidebarSection(
      id: id,
      title: title,
      slug: raw['slug']?.toString() ?? '',
      sectionType: raw['section_type']?.toString(),
      links: links,
    );
  }
}

/// The forum's own sidebar, per forum.
///
/// Discourse lets a community configure its sidebar — Feed, Scripture
/// Campaign, whatever a forum has added — and serves it two ways: a signed-in
/// member's own sections as `sidebar_sections` on `current_user`, and the
/// forum's defaults as `anonymous_sidebar_sections` on `/site.json`. Both
/// arrive in payloads the app already fetches.
///
/// Keeping it here means the drawer follows the forum: a link added in
/// Discourse appears in the app with no release. The member's own sections
/// win where both are known, because that is what the web shows them.
class DiscourseSidebarSections {
  DiscourseSidebarSections._();

  static final Map<String, List<DiscourseSidebarSection>> _own = {};
  static final Map<String, List<DiscourseSidebarSection>> _anonymous = {};

  /// `sidebar_sections` from `current_user`.
  static void storeFromCurrentUser(String siteUrl, Object? raw) =>
      _store(_own, siteUrl, raw);

  /// `anonymous_sidebar_sections` from `/site.json`.
  static void storeFromSite(String siteUrl, Object? raw) =>
      _store(_anonymous, siteUrl, raw);

  static void _store(
    Map<String, List<DiscourseSidebarSection>> into,
    String siteUrl,
    Object? raw,
  ) {
    if (raw is! List) return;
    final sections = raw
        .map(DiscourseSidebarSection.fromJson)
        .whereType<DiscourseSidebarSection>()
        .where((s) => s.links.isNotEmpty)
        .toList(growable: false);
    // An empty list is a real answer — a forum can have no sections — but
    // a payload that parsed to nothing from a non-empty list is not, and
    // overwriting good sections with it would empty the drawer.
    if (sections.isEmpty && raw.isNotEmpty) return;
    into[siteUrl] = sections;
  }

  /// What the drawer should show, the member's own sections ahead of the
  /// forum's defaults. Empty when neither has been read yet.
  static List<DiscourseSidebarSection> forSite(String siteUrl) =>
      _own[siteUrl] ?? _anonymous[siteUrl] ?? const [];

  /// Signing out drops the member's own sections; the forum's defaults
  /// stay, because they are the forum's, not theirs.
  static void clearOwn(String siteUrl) => _own.remove(siteUrl);

  @visibleForTesting
  static void reset() {
    _own.clear();
    _anonymous.clear();
  }
}
