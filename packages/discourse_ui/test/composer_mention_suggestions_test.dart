import 'package:discourse_core/discourse_core.dart'
    show DiscourseMentionCandidate, DiscourseSiteCapabilities;
import 'package:discourse_ui/l10n/generated/app_localizations.dart';
import 'package:discourse_ui/theme/app_theme.dart';
import 'package:discourse_ui/views/widgets/message_compose_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forumcopilot_sdk/context/site_context.dart';
import 'package:forumcopilot_sdk/models/domain/site.dart';

/// In the composer, typing `@` shows the topic's people as chips above the
/// toolbar, and a tap puts the mention in; the @ button still opens the
/// full search.
void main() {
  const url = 'https://forum.example';
  DiscourseMentionCandidate person(String username) =>
      (username: username, name: null, avatarUrl: null, isGroup: false);

  setUp(DiscourseSiteCapabilities.reset);

  Future<({TextEditingController text, List<String> asked})> open(
      WidgetTester tester) async {
    final text = TextEditingController();
    final asked = <String>[];
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.lightTheme,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: MessageComposePage(
        siteContext: _site(url),
        title: 'Reply',
        contentController: text,
        onSubmit: (_, __) async => true,
        mentionPeople: [person('ann'), person('bob')],
        mentionSearch: (term) async {
          asked.add(term);
          return term == 'ca' ? [person('cat')] : const [];
        },
      ),
    ));
    // Past the composer's delayed first focus, on the text.
    await tester.pumpAndSettle(const Duration(milliseconds: 150));
    return (text: text, asked: asked);
  }

  testWidgets('@ offers the topic\'s people, and a tap mentions one',
      (tester) async {
    final c = await open(tester);
    expect(find.byType(ActionChip), findsNothing);
    expect(find.byTooltip('Mention User'), findsOneWidget,
        reason: 'the full search stays');

    await tester.enterText(find.byType(TextField), 'Thanks @');
    await tester.pump();
    expect(find.widgetWithText(ActionChip, 'ann'), findsOneWidget);
    expect(find.widgetWithText(ActionChip, 'bob'), findsOneWidget);

    await tester.tap(find.widgetWithText(ActionChip, 'bob'));
    await tester.pump();
    expect(c.text.text, 'Thanks @bob ');
    expect(c.text.selection.baseOffset, 'Thanks @bob '.length);
    expect(find.byType(ActionChip), findsNothing,
        reason: 'the mention is done');
  });

  testWidgets('the forum\'s matches join from the second letter',
      (tester) async {
    final c = await open(tester);
    await tester.enterText(find.byType(TextField), '@c');
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(ActionChip), findsNothing);
    expect(c.asked, isNot(contains('c')));

    await tester.enterText(find.byType(TextField), '@ca');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    expect(c.asked, contains('ca'));
    expect(find.widgetWithText(ActionChip, 'cat'), findsOneWidget);
  });

  testWidgets('a forum with mentions off offers none, nor the @ button',
      (tester) async {
    DiscourseSiteCapabilities.storeClientSettings(url, {'enable_mentions': false});
    final c = await open(tester);
    await tester.enterText(find.byType(TextField), '@');
    await tester.pump();
    expect(find.byType(ActionChip), findsNothing);
    expect(find.byTooltip('Mention User'), findsNothing);
    expect(c.asked, isEmpty);
  });
}

SiteContext _site(String url) => SiteContext(
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
    );
