import 'package:discourse_core/discourse_core.dart'
    show DiscourseSiteCapabilities;
import 'package:discourse_ui/l10n/generated/app_localizations.dart';
import 'package:discourse_ui/theme/app_theme.dart';
import 'package:discourse_ui/utils/discourse_poll_markup.dart';
import 'package:discourse_ui/views/widgets/message_compose_page.dart';
import 'package:discourse_ui/views/widgets/poll_builder_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forumcopilot_sdk/forumcopilot_sdk.dart';

/// The composer builds a poll instead of leaving a member to type `[poll]`
/// markup, as the Flarum app's composer does: a full-screen builder with
/// Discourse's own options, whose block goes in the text, and a chip for
/// each poll in the text that opens it again or takes it out.
void main() {
  const url = 'https://polls.example';

  /// A phone's screen (the Pixel 10a's, 411×914 dp), not the test's
  /// 800×600 landscape.
  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
  }

  Widget app(Widget home) => MaterialApp(
        theme: AppTheme.lightTheme,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: home,
      );

  group('the builder', () {
    Future<List<DiscoursePoll?>> open(WidgetTester tester,
        {DiscoursePoll? poll, int maxOptions = 20}) async {
      phone(tester);
      final results = <DiscoursePoll?>[];
      await tester.pumpWidget(app(Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async => results.add(await PollBuilderPage.open(
                context,
                maxOptions: maxOptions,
                defaultPublic: false,
                poll: poll)),
            child: const Text('open'),
          ),
        ),
      )));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return results;
    }

    Finder field(String label) => find.widgetWithText(TextField, label);

    Future<void> insert(WidgetTester tester, [String label = 'Insert']) async {
      await tester.tap(find.widgetWithText(FilledButton, label));
      await tester.pumpAndSettle();
    }

    testWidgets('a single-choice poll', (tester) async {
      final results = await open(tester);
      await tester.enterText(field('Title (optional)'), 'Lunch?');
      await tester.enterText(field('Option 1'), 'Pizza');
      await tester.enterText(field('Option 2'), 'Soup');
      await insert(tester);
      expect(results.single?.toMarkup(),
          '[poll type=regular results=always public=false chartType=bar]\n'
          '# Lunch?\n* Pizza\n* Soup\n[/poll]',
          reason: 'public follows the forum\'s poll_default_public');
    });

    testWidgets('Add option puts the cursor in the new option',
        (tester) async {
      await open(tester);
      await tester.tap(field('Option 1'));
      await tester.tap(find.text('Add option'));
      await tester.pumpAndSettle();
      bool focused(String label) => tester
          .widget<EditableText>(find.descendant(
              of: field(label), matching: find.byType(EditableText)))
          .focusNode
          .hasFocus;
      expect(focused('Option 3'), isTrue);
      expect(focused('Option 1'), isFalse);
    });

    testWidgets('a closing time is picked without the keyboard coming back',
        (tester) async {
      final results = await open(tester);
      await tester.tap(field('Title (optional)'));
      await tester.enterText(field('Option 1'), 'Yes');
      await tester.tap(find.text('Close automatically'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK')); // the day
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK')); // the time
      await tester.pumpAndSettle();
      expect(
          tester
              .widgetList<EditableText>(find.byType(EditableText))
              .where((e) => e.focusNode.hasFocus),
          isEmpty,
          reason: 'no field takes the cursor back, so no keyboard');
      await insert(tester);
      expect(results.single?.close, isNotNull);
    });

    testWidgets('no options, or the same one twice, is said under them',
        (tester) async {
      final results = await open(tester);
      await insert(tester);
      expect(find.text('Add at least one option'), findsOneWidget);
      expect(results, isEmpty, reason: 'the builder stays open');

      await tester.enterText(field('Option 1'), 'Same');
      await tester.pump();
      expect(find.text('Add at least one option'), findsNothing,
          reason: 'editing puts it right');
      await tester.enterText(field('Option 2'), 'Same');
      await insert(tester);
      expect(find.text('Each option must be different'), findsOneWidget);
    });

    testWidgets('multiple choice: the bounds cannot go wrong', (tester) async {
      final results = await open(tester);
      await tester.tap(find.text('Multiple choice'));
      await tester.pumpAndSettle();
      await tester.enterText(field('Option 1'), 'A');
      await tester.enterText(field('Option 2'), 'B');
      await tester.tap(find.text('Add option'));
      await tester.pumpAndSettle();
      await tester.enterText(field('Option 3'), 'C');
      await tester.pumpAndSettle();

      // At least 1 of 3; at most 3, all of them.
      final moreAtLeast = find.widgetWithIcon(IconButton, Icons.add).first;
      await tester.ensureVisible(moreAtLeast);
      await tester.pumpAndSettle();
      await tester.tap(moreAtLeast);
      await tester.pumpAndSettle();
      expect(tester.widget<IconButton>(moreAtLeast).onPressed, isNull,
          reason: 'a voter must leave one out: at least 2 of 3 is the most');
      await insert(tester);
      final poll = results.single!;
      expect((poll.type, poll.min, poll.max), (DiscoursePollType.multiple, 2, 3));
    });

    testWidgets('number rating: too few numbers, or too many', (tester) async {
      final results = await open(tester, maxOptions: 20);
      await tester.tap(find.text('Number rating'));
      await tester.pumpAndSettle();
      expect(field('Option 1'), findsNothing);
      await tester.enterText(field('Maximum'), '1');
      await insert(tester);
      expect(find.text('Leaves fewer than two numbers to choose from'),
          findsOneWidget);

      await tester.enterText(field('Maximum'), '100');
      await insert(tester);
      expect(find.text('Makes more than 20 numbers to choose from'),
          findsOneWidget);

      await tester.enterText(field('Step'), '10');
      await insert(tester);
      expect(results.single?.toMarkup(),
          '[poll type=number results=always min=1 max=100 step=10 public=false]\n'
          '[/poll]');
    });

    testWidgets('editing keeps the poll\'s name and what it does not show',
        (tester) async {
      final poll = DiscoursePoll.findIn(
              '[poll name=poll2 type=regular public=true groups=team]\n# Old\n* A\n* B\n[/poll]')
          .single
          .poll;
      final results = await open(tester, poll: poll);
      expect(find.text('Edit poll'), findsOneWidget);
      await tester.enterText(field('Title (optional)'), 'New');
      await insert(tester, 'Save');
      expect(results.single?.toMarkup(),
          '[poll name=poll2 type=regular results=always public=true chartType=bar groups=team]\n'
          '# New\n* A\n* B\n[/poll]');
    });
  });

  group('in the composer', () {
    late SiteContext site;

    setUp(() {
      DiscourseSiteCapabilities.reset();
      site = SiteContext(
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
      )..setLoginData(FCLoginResult(
          result: true, resultText: '', user: FCUser(id: '2', username: 'alice')));
    });

    void allowPolls() {
      DiscourseSiteCapabilities.storeClientSettings(url, {
        'poll_enabled': true,
        'poll_maximum_options': 20,
        'poll_default_public': true,
      });
      DiscourseSiteCapabilities.storeCurrentUser(url, {'can_create_poll': true});
    }

    Future<TextEditingController> open(WidgetTester tester) async {
      phone(tester);
      final text = TextEditingController(text: 'Before\nAfter');
      await tester.pumpWidget(app(MessageComposePage(
        siteContext: site,
        title: 'Reply',
        autoFocusContent: false,
        contentController: text,
        onSubmit: (_, __) async => true,
      )));
      await tester.pumpAndSettle(const Duration(milliseconds: 150));
      text.selection = const TextSelection.collapsed(offset: 6);
      return text;
    }

    testWidgets('offered only where the forum lets the reader make polls',
        (tester) async {
      await open(tester);
      expect(find.byTooltip('Build poll'), findsNothing);

      DiscourseSiteCapabilities.storeClientSettings(url, {'poll_enabled': true});
      await open(tester);
      expect(find.byTooltip('Build poll'), findsNothing,
          reason: 'the reader may not create polls');

      allowPolls();
      await open(tester);
      expect(find.byTooltip('Build poll'), findsOneWidget);
    });

    testWidgets('the poll goes at the cursor, with a chip to edit or remove it',
        (tester) async {
      allowPolls();
      final text = await open(tester);
      await tester.tap(find.byTooltip('Build poll'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Title (optional)'), 'Lunch?');
      await tester.enterText(find.widgetWithText(TextField, 'Option 1'), 'Pizza');
      await tester.enterText(find.widgetWithText(TextField, 'Option 2'), 'Soup');
      await tester.tap(find.widgetWithText(FilledButton, 'Insert'));
      await tester.pumpAndSettle();

      expect(text.text,
          'Before\n[poll type=regular results=always public=true chartType=bar]\n'
          '# Lunch?\n* Pizza\n* Soup\n[/poll]\nAfter');
      expect(find.widgetWithText(InputChip, 'Lunch?'), findsOneWidget);

      // Open it again: the builder has what it had.
      await tester.tap(find.widgetWithText(InputChip, 'Lunch?'));
      await tester.pumpAndSettle();
      expect(find.text('Edit poll'), findsOneWidget);
      await tester.enterText(find.widgetWithText(TextField, 'Option 2'), 'Salad');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      expect(text.text, contains('* Salad\n'));
      expect(text.text, isNot(contains('Soup')));

      // A second poll needs a name of its own.
      text.selection = TextSelection.collapsed(offset: text.text.length);
      await tester.tap(find.byTooltip('Build poll'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Option 1'), 'Yes');
      await tester.tap(find.widgetWithText(FilledButton, 'Insert'));
      await tester.pumpAndSettle();
      expect(text.text, contains('[poll name=poll2 '));
      expect(find.byType(InputChip), findsNWidgets(2));

      // Its chip's ✕ takes it out of the text.
      await tester.tap(find.byTooltip('Remove poll').first);
      await tester.pumpAndSettle();
      expect(text.text, isNot(contains('Lunch?')));
      expect(text.text, startsWith('Before\nAfter'));
      expect(find.byType(InputChip), findsOneWidget);
    });
  });
}
