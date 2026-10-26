import 'package:discourse_ui/l10n/generated/app_localizations.dart';
import 'package:discourse_ui/theme/app_theme.dart';
import 'package:discourse_ui/views/widgets/message_compose_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forumcopilot_sdk/context/site_context.dart';
import 'package:forumcopilot_sdk/models/domain/site.dart';

/// An empty title or text is said under the field itself, and goes as soon
/// as the writer types there. Send used to show a SnackBar that pointed at
/// nothing and was gone by the time the writer looked for the field.
void main() {
  const missingTitle = 'Please enter a title';
  const missingContent = 'Please enter some content';

  Future<List<String>> open(WidgetTester tester,
      {bool requireTitle = true}) async {
    final sent = <String>[];
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.lightTheme,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: MessageComposePage(
        siteContext: _site(),
        title: 'New Topic',
        submitLabel: 'Create Topic',
        showTitleField: true,
        requireTitle: requireTitle,
        autoFocusContent: false,
        onSubmit: (title, content) async {
          sent.add('$title|$content');
          return false;
        },
      ),
    ));
    await tester.pumpAndSettle();
    return sent;
  }

  Finder titleField() => find.byType(TextField).first;
  Finder contentField() => find.byType(TextField).last;

  InputDecoration decorationOf(WidgetTester tester, Finder field) =>
      tester.widget<TextField>(field).decoration!;

  Future<void> send(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(FilledButton, 'Create Topic'));
    await tester.pumpAndSettle();
  }

  testWidgets('an empty title says so under the title, not in a SnackBar',
      (tester) async {
    final sent = await open(tester);
    await tester.enterText(contentField(), 'Some text');
    await send(tester);

    expect(decorationOf(tester, titleField()).errorText, missingTitle);
    expect(decorationOf(tester, contentField()).error, isNull);
    expect(find.text(missingContent), findsNothing);
    expect(find.byType(SnackBar), findsNothing);
    expect(sent, isEmpty);
    expect(tester.widget<EditableText>(find.descendant(
            of: titleField(), matching: find.byType(EditableText)))
        .focusNode
        .hasFocus, isTrue, reason: 'the cursor goes to the field');
  });

  testWidgets('typing in the field takes its error away', (tester) async {
    await open(tester);
    await send(tester);
    expect(find.text(missingTitle), findsOneWidget);
    expect(find.text(missingContent), findsOneWidget);

    await tester.enterText(titleField(), 'A title');
    await tester.pump();
    expect(find.text(missingTitle), findsNothing);
    expect(find.text(missingContent), findsOneWidget,
        reason: 'the other field is still empty');

    await tester.enterText(contentField(), 'Some text');
    await tester.pump();
    expect(find.text(missingContent), findsNothing);
  });

  testWidgets('spaces alone are still empty', (tester) async {
    await open(tester);
    await tester.enterText(titleField(), 'A title');
    await tester.enterText(contentField(), '   ');
    await send(tester);
    expect(decorationOf(tester, contentField()).error, isNotNull,
        reason: 'outlined in red');
    expect(find.text(missingContent), findsOneWidget);
  });

  testWidgets('with the keyboard up, the empty text is said above it',
      (tester) async {
    // A phone (411×914 dp) with its keyboard taking 330 dp. The text is
    // ten lines tall, so its own error line was under the keyboard.
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    tester.view.viewInsets = const FakeViewPadding(bottom: 330 * 2.625);
    addTearDown(tester.view.reset);
    await open(tester);
    await tester.enterText(titleField(), 'A title');
    await send(tester);

    final keyboardTop = 2400 / 2.625 - 330;
    expect(tester.getRect(find.text(missingContent)).bottom,
        lessThanOrEqualTo(keyboardTop));
    expect(tester.getRect(find.text(missingContent)).top,
        greaterThanOrEqualTo(tester.getRect(find.byType(Scrollable).first).bottom),
        reason: 'under the page with the field, not inside it');
    expect(tester.getRect(find.text(missingContent)).left,
        tester.getRect(contentField()).left,
        reason: 'at the start of the line, as the field\'s own error');
    expect(decorationOf(tester, contentField()).error, isNotNull);
  });

  testWidgets('both filled in, it sends', (tester) async {
    final sent = await open(tester);
    await tester.enterText(titleField(), 'A title');
    await tester.enterText(contentField(), 'Some text');
    await send(tester);
    expect(sent, ['A title|Some text']);
    expect(find.text(missingTitle), findsNothing);
    expect(find.text(missingContent), findsNothing);
  });

  testWidgets('an edit with no title to keep does not ask for one',
      (tester) async {
    final sent = await open(tester, requireTitle: false);
    await tester.enterText(contentField(), 'Some text');
    await send(tester);
    expect(find.text(missingTitle), findsNothing);
    expect(sent, ['|Some text']);
  });
}

SiteContext _site() => SiteContext(
      siteType: 'discourse',
      site: Site(
        id: null,
        name: 'Test',
        url: 'https://forum.example',
        description: '',
        endpoint: null,
        baseUrl: 'https://forum.example',
        logoUrl: null,
        backgroundUrl: null,
        siteType: 'discourse',
      ),
    );
