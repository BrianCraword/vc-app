import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../theme/design_tokens.dart';
import '../../utils/discourse_poll_markup.dart';
import 'discard_changes_scope.dart';

/// Builds a Discourse poll for the composer to put in the post, with the
/// options the web's poll builder offers: single choice, multiple choice
/// (how many a voter picks) or a number rating, a title, the options, who
/// sees the results and when, whether voters are shown, when it closes,
/// and a bar or pie chart. A full-screen page, as long forms are on a
/// phone; Done hands the poll back.
///
/// It checks what the forum would refuse (PollsValidator): no options, the
/// same option twice, more than the forum's [maxOptions], a number rating
/// with fewer than two numbers, a closing time already past. Each says so
/// under its field.
class PollBuilderPage extends StatefulWidget {
  const PollBuilderPage({
    super.key,
    required this.maxOptions,
    this.defaultPublic = true,
    this.poll,
  });

  /// `poll_maximum_options`.
  final int maxOptions;

  /// `poll_default_public`: whether a new poll shows who voted.
  final bool defaultPublic;

  /// The poll being changed; null for a new one.
  final DiscoursePoll? poll;

  static Future<DiscoursePoll?> open(
    BuildContext context, {
    required int maxOptions,
    bool defaultPublic = true,
    DiscoursePoll? poll,
  }) =>
      Navigator.of(context).push(MaterialPageRoute<DiscoursePoll>(
        fullscreenDialog: true,
        builder: (_) => PollBuilderPage(
          maxOptions: maxOptions,
          defaultPublic: defaultPublic,
          poll: poll,
        ),
      ));

  @override
  State<PollBuilderPage> createState() => _PollBuilderPageState();
}

class _PollBuilderPageState extends State<PollBuilderPage> {
  late DiscoursePollType _type = widget.poll?.type ?? DiscoursePollType.regular;
  late final _title = _field(widget.poll?.title ?? '');
  late final List<TextEditingController> _options = [
    for (final o in (widget.poll?.options.isNotEmpty ?? false)
        ? widget.poll!.options
        : const ['', ''])
      _field(o),
  ];

  /// The option Add option just made, which takes the cursor.
  TextEditingController? _added;
  final _addedFocus = FocusNode();

  /// Multiple choice: how many a voter picks; null for "all of them".
  late int _minChoices = (widget.poll?.type == DiscoursePollType.multiple
          ? widget.poll?.min
          : null) ??
      1;
  late int? _maxChoices = widget.poll?.type == DiscoursePollType.multiple
      ? widget.poll?.max
      : null;

  /// Number rating: the web's defaults, 1 to 10.
  late final _numberMin = _field(_numberText(widget.poll?.min, 1));
  late final _numberMax = _field(_numberText(widget.poll?.max, 10));
  late final _numberStep = _field(_numberText(widget.poll?.step, 1));

  late DiscoursePollResults _results =
      widget.poll?.results ?? DiscoursePollResults.always;
  late bool _public = widget.poll?.isPublic ?? widget.defaultPublic;
  late DateTime? _close = widget.poll?.close;
  late DiscoursePollChart _chart = widget.poll?.chart ?? DiscoursePollChart.bar;

  /// What Done found wrong, each shown under its field until it is edited.
  String? _optionsError;
  String? _numberMinError;
  String? _numberMaxError;
  String? _numberStepError;
  String? _closeError;

  /// Bumped by every edit, for the close prompt to follow.
  final _edits = ValueNotifier(0);
  late final String _opened = _snapshot();

  String _numberText(int? value, int fallback) =>
      '${widget.poll?.type == DiscoursePollType.number ? value ?? fallback : fallback}';

  String _snapshot() => [
        _type,
        _title.text,
        for (final o in _options) o.text,
        _minChoices,
        _maxChoices,
        _numberMin.text,
        _numberMax.text,
        _numberStep.text,
        _results,
        _public,
        _close,
        _chart,
      ].join('\u0000');

  /// A change the writer made: rebuilt, counted as an edit, and what Done
  /// found wrong is gone (they are putting it right).
  void _edit(VoidCallback change) {
    setState(() {
      change();
      _clearErrors();
    });
    _edits.value++;
  }

  void _clearErrors() {
    _optionsError = null;
    _numberMinError = null;
    _numberMaxError = null;
    _numberStepError = null;
    _closeError = null;
  }

  TextEditingController _field(String text) {
    final controller = TextEditingController(text: text);
    var last = text;
    controller.addListener(() {
      // Only a change of text: moving the cursor notifies too.
      if (controller.text == last) return;
      last = controller.text;
      if (mounted) _edit(() {});
    });
    return controller;
  }

  /// One more option, with the cursor in it. (Autofocus would not take
  /// it from the option being typed in.)
  void _addOption() {
    _edit(() => _options.add(_added = _field('')));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _addedFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _edits.dispose();
    _addedFocus.dispose();
    _title.dispose();
    for (final o in _options) {
      o.dispose();
    }
    _numberMin.dispose();
    _numberMax.dispose();
    _numberStep.dispose();
    super.dispose();
  }

  List<String> get _filled => [
        for (final o in _options)
          if (o.text.trim().isNotEmpty) o.text.trim(),
      ];

  /// Multiple choice's bounds for the options there are: at least one and
  /// fewer than all (a voter must leave one out), at most all of them.
  int get _optionCount => _filled.length < 2 ? 2 : _filled.length;
  int get _effectiveMax =>
      (_maxChoices ?? _optionCount).clamp(1, _optionCount);
  int get _effectiveMin => _minChoices.clamp(1, _effectiveMax.clamp(1, _optionCount - 1));

  Future<void> _chooseClose() async {
    // The pickers give focus back to the field that had it, and the
    // keyboard came up again over the time just chosen. (The field's own
    // unfocus: the page's scope would still remember it.)
    FocusManager.instance.primaryFocus?.unfocus();
    final now = DateTime.now();
    final initial = _close ?? now.add(const Duration(days: 7));
    final day = await showDatePicker(
      context: context,
      initialDate: initial.isBefore(now) ? now : initial,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365 * 10)),
    );
    if (day == null || !mounted) return;
    final time = await showTimePicker(
        context: context, initialTime: TimeOfDay.fromDateTime(initial));
    if (time == null || !mounted) return;
    _edit(() =>
        _close = DateTime(day.year, day.month, day.day, time.hour, time.minute));
  }

  void _done() {
    final l10n = AppLocalizations.of(context)!;
    final options = _filled;
    _clearErrors();
    int? numberMin, numberMax, numberStep;
    if (_type == DiscoursePollType.number) {
      numberMin = int.tryParse(_numberMin.text.trim());
      numberMax = int.tryParse(_numberMax.text.trim());
      numberStep = int.tryParse(_numberStep.text.trim());
      if (numberMin == null) _numberMinError = l10n.pollEnterNumber;
      if (numberMax == null) _numberMaxError = l10n.pollEnterNumber;
      if (numberStep == null) {
        _numberStepError = l10n.pollEnterNumber;
      } else if (numberStep < 1) {
        _numberStepError = l10n.pollStepTooSmall;
      }
      if (numberMin != null && numberMax != null && (numberStep ?? 0) >= 1) {
        final count = (numberMax - numberMin) ~/ numberStep! + 1;
        if (numberMax < numberMin || (numberMax - numberMin + 1) ~/ numberStep < 2) {
          _numberMaxError = l10n.pollNumberTooFew;
        } else if (count > widget.maxOptions) {
          _numberMaxError = l10n.pollNumberTooMany(widget.maxOptions);
        }
      }
    } else if (options.isEmpty) {
      _optionsError = l10n.pollNeedsOption;
    } else if (options.toSet().length != options.length) {
      _optionsError = l10n.pollOptionsMustDiffer;
    } else if (options.length > widget.maxOptions) {
      _optionsError = l10n.pollTooManyOptions(widget.maxOptions);
    } else if (_type == DiscoursePollType.multiple && options.length < 2) {
      _optionsError = l10n.pollMultipleNeedsTwo;
    }
    final close = _close;
    if (close != null && !close.isAfter(DateTime.now())) {
      _closeError = l10n.pollCloseInPast;
    }
    if (_optionsError != null ||
        _numberMinError != null ||
        _numberMaxError != null ||
        _numberStepError != null ||
        _closeError != null) {
      setState(() {});
      return;
    }
    final multiple = _type == DiscoursePollType.multiple;
    Navigator.of(context).pop(DiscoursePoll(
      name: widget.poll?.name,
      type: _type,
      title: _title.text.trim(),
      options: _type == DiscoursePollType.number ? const [] : options,
      min: multiple ? _effectiveMin : numberMin,
      max: multiple ? _effectiveMax : numberMax,
      step: numberStep,
      results: _results,
      isPublic: _public,
      close: close,
      chart: _chart,
      extra: widget.poll?.extra ?? const {},
    ));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final locale = Localizations.localeOf(context).toString();
    final number = _type == DiscoursePollType.number;
    Widget heading(String text) => Padding(
          padding: const EdgeInsets.only(
              top: DesignTokens.spacingL, bottom: DesignTokens.spacingXS),
          child: Text(text,
              style: theme.textTheme.titleSmall
                  ?.copyWith(color: colorScheme.primary)),
        );
    final digits = [FilteringTextInputFormatter.digitsOnly];

    return DiscardChangesScope(
      listenable: _edits,
      hasChanges: () => _snapshot() != _opened,
      isEdit: true,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.poll == null ? l10n.pollBuild : l10n.pollEdit),
          leading: IconButton(
            icon: const Icon(Icons.close),
            tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          actions: [
            Padding(
              padding: const EdgeInsetsDirectional.only(
                  end: DesignTokens.spacingS),
              child: FilledButton(
                onPressed: _done,
                child: Text(widget.poll == null ? l10n.pollInsert : l10n.save),
              ),
            ),
          ],
        ),
        body: ListView(
          padding: DesignTokens.paddingL,
          children: [
            RadioGroup<DiscoursePollType>(
              groupValue: _type,
              onChanged: (t) {
                if (t != null) _edit(() => _type = t);
              },
              child: Column(
                children: [
                  for (final (type, label) in [
                    (DiscoursePollType.regular, l10n.pollTypeRegular),
                    (DiscoursePollType.multiple, l10n.pollTypeMultiple),
                    (DiscoursePollType.number, l10n.pollTypeNumber),
                  ])
                    RadioListTile<DiscoursePollType>(
                      contentPadding: EdgeInsets.zero,
                      value: type,
                      title: Text(label),
                    ),
                ],
              ),
            ),
            const SizedBox(height: DesignTokens.spacingS),
            TextField(
              controller: _title,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(labelText: l10n.pollTitleOptional),
            ),
            if (!number) ...[
              heading(l10n.options),
              for (final (i, option) in _options.indexed)
                Padding(
                  key: ObjectKey(option),
                  padding: const EdgeInsets.only(bottom: DesignTokens.spacingS),
                  child: TextField(
                    controller: option,
                    focusNode: identical(option, _added) ? _addedFocus : null,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      labelText: l10n.pollOptionLabel(i + 1),
                      // Under the last option, where the list ends.
                      errorText: i == _options.length - 1 ? _optionsError : null,
                      errorMaxLines: 3,
                      suffixIcon: _options.length > 1
                          ? IconButton(
                              icon: const Icon(Icons.remove_circle_outline),
                              tooltip: l10n.pollRemoveOption,
                              onPressed: () =>
                                  _edit(() => _options.removeAt(i).dispose()),
                            )
                          : null,
                    ),
                  ),
                ),
              if (_options.length < widget.maxOptions)
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton.icon(
                    onPressed: _addOption,
                    icon: const Icon(Icons.add),
                    label: Text(l10n.pollAddOption),
                  ),
                ),
            ],
            if (_type == DiscoursePollType.multiple) ...[
              _Stepper(
                label: l10n.pollMinChoices,
                value: _effectiveMin,
                min: 1,
                max: (_optionCount - 1).clamp(1, _effectiveMax),
                onChanged: (v) => _edit(() => _minChoices = v),
              ),
              _Stepper(
                label: l10n.pollMaxChoices,
                value: _effectiveMax,
                min: _effectiveMin,
                max: _optionCount,
                onChanged: (v) => _edit(() => _maxChoices = v),
              ),
            ],
            if (number) ...[
              const SizedBox(height: DesignTokens.spacingL),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final (controller, label, error) in [
                    (_numberMin, l10n.pollNumberMin, _numberMinError),
                    (_numberMax, l10n.pollNumberMax, _numberMaxError),
                    (_numberStep, l10n.pollNumberStep, _numberStepError),
                  ]) ...[
                    if (controller != _numberMin)
                      const SizedBox(width: DesignTokens.spacingS),
                    Expanded(
                      child: TextField(
                        controller: controller,
                        keyboardType: TextInputType.number,
                        inputFormatters: digits,
                        decoration: InputDecoration(
                          labelText: label,
                          errorText: error,
                          errorMaxLines: 4,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
            const Divider(height: DesignTokens.spacingXL),
            heading(l10n.pollResultsLabel),
            RadioGroup<DiscoursePollResults>(
              groupValue: _results,
              onChanged: (r) {
                if (r != null) _edit(() => _results = r);
              },
              child: Column(
                children: [
                  for (final (results, label) in [
                    (DiscoursePollResults.always, l10n.pollResultsAlways),
                    (DiscoursePollResults.onVote, l10n.pollResultsOnVote),
                    (DiscoursePollResults.onClose, l10n.pollResultsOnClose),
                    (DiscoursePollResults.staffOnly, l10n.pollResultsStaffOnly),
                  ])
                    RadioListTile<DiscoursePollResults>(
                      contentPadding: EdgeInsets.zero,
                      value: results,
                      title: Text(label),
                    ),
                ],
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.pollShowWhoVoted),
              value: _public,
              onChanged: (v) => _edit(() => _public = v),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.pollCloseAutomatically),
              subtitle: Text(
                _closeError ??
                    (_close == null
                        ? l10n.pollNeverCloses
                        : DateFormat.yMMMd(locale).add_jm().format(_close!)),
                style: _closeError == null
                    ? null
                    : TextStyle(color: colorScheme.error),
              ),
              onTap: _chooseClose,
              trailing: _close == null
                  ? const Icon(Icons.event_outlined)
                  : IconButton(
                      icon: const Icon(Icons.clear),
                      tooltip: l10n.pollDontClose,
                      onPressed: () => _edit(() => _close = null),
                    ),
            ),
            if (!number) ...[
              heading(l10n.pollChart),
              SegmentedButton<DiscoursePollChart>(
                segments: [
                  ButtonSegment(
                    value: DiscoursePollChart.bar,
                    icon: const Icon(Icons.bar_chart),
                    label: Text(l10n.pollChartBar),
                  ),
                  ButtonSegment(
                    value: DiscoursePollChart.pie,
                    icon: const Icon(Icons.pie_chart_outline),
                    label: Text(l10n.pollChartPie),
                  ),
                ],
                selected: {_chart},
                onSelectionChanged: (s) => _edit(() => _chart = s.first),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A number picked with − and +, kept between [min] and [max]: a choice
/// the forum would refuse cannot be made.
class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.remove),
            tooltip: l10n.pollFewer,
            onPressed: value > min ? () => onChanged(value - 1) : null,
          ),
          SizedBox(
            width: 32,
            child: Text('$value',
                textAlign: TextAlign.center,
                semanticsLabel: '$label $value',
                style: Theme.of(context).textTheme.titleMedium),
          ),
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: l10n.pollMore,
            onPressed: value < max ? () => onChanged(value + 1) : null,
          ),
        ],
      ),
    );
  }
}
