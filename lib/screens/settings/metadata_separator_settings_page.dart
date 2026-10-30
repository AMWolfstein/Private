import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sistrum/l10n/l10n.dart';
import 'package:sistrum/models/metadata_separators.dart';
import 'package:sistrum/models/tag_credit_settings.dart';
import 'package:sistrum/services/library/library_tag_credits.dart';
import 'package:sistrum/providers/settings_provider.dart';
import 'package:sistrum/utils/nav_bar_inset.dart';
import 'package:sistrum/widgets/primitives/app_alert_dialog.dart';
import 'package:sistrum/widgets/primitives/app_bottom_sheet.dart';
import 'package:sistrum/widgets/primitives/app_choice_chip.dart';
import 'package:sistrum/widgets/primitives/app_content_card.dart';
import 'package:sistrum/widgets/primitives/app_sliver_header.dart';
import 'package:sistrum/widgets/settings/settings_group.dart';
import 'package:sistrum/widgets/settings/settings_item_rows.dart';

/// Tag separators: which delimiters split credits in the library, the separator
/// that joins names when tags are saved, and names that are never split.
class MetadataSeparatorSettingsPage extends ConsumerWidget {
  const MetadataSeparatorSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final separators = ref.watch(
      settingsProvider.select((s) => s.metadataSeparators),
    );
    final credits = ref.watch(settingsProvider.select((s) => s.tagCredits));
    final notifier = ref.read(settingsProvider.notifier);
    final l10n = context.l10n;
    final rules = TagCreditRules.fromSettings(credits);
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          AppSliverHeader.page(title: l10n.metadataSeparators),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
              child: Text(l10n.metadataSeparatorsDescription),
            ),
          ),
          SliverToBoxAdapter(
            child: SettingsSectionHeader(title: l10n.tagSeparatorsArtists),
          ),
          SliverToBoxAdapter(
            child: _DelimiterSection(
              caption: l10n.tagSeparatorsArtistsFields,
              field: TagCreditField.artist,
              rules: rules,
              choices: kArtistDelimiterChoices,
              custom: credits.customArtistDelimiters,
              selected: credits.artistDelimiters,
              saveWithLabel: l10n.editMetadataFieldArtist,
              saveWith: separators.names,
              onToggle: notifier.toggleArtistDelimiter,
              onToggleAll: notifier.toggleAllArtistDelimiters,
              onAdd: notifier.addArtistDelimiter,
              onRemoveCustom: notifier.removeCustomArtistDelimiter,
              onSaveWith: notifier.setMetadataNamesSeparator,
            ),
          ),
          SliverToBoxAdapter(
            child: SettingsSectionHeader(title: l10n.tagSeparatorsGenre),
          ),
          SliverToBoxAdapter(
            child: _DelimiterSection(
              field: TagCreditField.genre,
              rules: rules,
              choices: kGenreDelimiterChoices,
              custom: credits.customGenreDelimiters,
              selected: credits.genreDelimiters,
              saveWithLabel: l10n.editMetadataFieldGenre,
              saveWith: separators.genre,
              onToggle: notifier.toggleGenreDelimiter,
              onToggleAll: notifier.toggleAllGenreDelimiters,
              onAdd: notifier.addGenreDelimiter,
              onRemoveCustom: notifier.removeCustomGenreDelimiter,
              onSaveWith: (value) =>
                  notifier.setMetadataSeparator('genre', value),
            ),
          ),
          SliverToBoxAdapter(
            child: _KeepTogetherSection(
              names: credits.keepTogether,
              onAdd: notifier.addKeepTogether,
              onRemove: notifier.removeKeepTogether,
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 32)),
          const NavBarSliverSpacer(),
        ],
      ),
    );
  }
}

/// One section: a chip grid of delimiters followed by the Save with row.
class _DelimiterSection extends StatelessWidget {
  const _DelimiterSection({
    this.caption,
    required this.field,
    required this.rules,
    required this.choices,
    required this.custom,
    required this.selected,
    required this.saveWithLabel,
    required this.saveWith,
    required this.onToggle,
    required this.onToggleAll,
    required this.onAdd,
    required this.onRemoveCustom,
    required this.onSaveWith,
  });

  /// The fields a section covers, when its header alone does not say.
  final String? caption;
  final TagCreditField field;
  final TagCreditRules rules;
  final List<String> choices;
  final List<String> custom;
  final List<String> selected;
  final String saveWithLabel;
  final String saveWith;
  final ValueChanged<String> onToggle;
  final VoidCallback onToggleAll;
  final ValueChanged<String> onAdd;
  final ValueChanged<String> onRemoveCustom;
  final ValueChanged<String> onSaveWith;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final offered = [...choices, ...custom];
    final allSelected = offered.every(selected.contains);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (caption case final caption?)
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
            child: Text(caption, style: Theme.of(context).textTheme.bodyMedium),
          ),
        _ChipGrid(
          children: [
            AppChoiceChip(
              label: _ChipLabel(l10n.tagSeparatorsAll),
              selected: allSelected,
              onSelected: (_) => onToggleAll(),
            ),
            for (final token in choices)
              _delimiterChip(context, token: token, custom: false),
            for (final token in custom)
              _delimiterChip(context, token: token, custom: true),
            AppChoiceChip(
              label: _ChipLabel(l10n.tagSeparatorsAdd),
              icon: const Icon(Icons.add, size: 18),
              selected: false,
              onSelected: (_) => _openAddSheet(context, offered),
            ),
          ],
        ),
        const SizedBox(height: 16),
        SettingsGroup(
          children: [
            SettingsItem(
              icon: Icons.save_alt_outlined,
              title: l10n.tagSeparatorsSaveWith,
              subtitle: saveWith.isEmpty
                  ? l10n.metadataSeparatorSource
                  : formatTagCreditsForSave(
                      '$saveWithLabel A, $saveWithLabel B',
                      field,
                      rules,
                      saveWith,
                    ),
              showDivider: false,
              onTap: () async {
                final value = await showAppBottomSheet<String>(
                  context: context,
                  useRootNavigator: true,
                  title: l10n.tagSeparatorsSaveWith,
                  builder: (_) =>
                      _SeparatorPicker(
                        label: saveWithLabel,
                        current: saveWith,
                        field: field,
                        rules: rules,
                      ),
                );
                if (value != null && context.mounted) onSaveWith(value);
              },
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
          child: Text(
            l10n.tagSeparatorsSaveWithDescription,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }

  Widget _delimiterChip(
    BuildContext context, {
    required String token,
    required bool custom,
  }) {
    final chip = AppChoiceChip(
      label: _ChipLabel(token),
      selected: selected.contains(token),
      onSelected: (_) => onToggle(token),
    );
    if (!custom) return chip;
    // A custom chip is removed by long press, after confirming.
    return GestureDetector(
      onLongPress: () => _confirmRemove(context, token),
      child: chip,
    );
  }

  Future<void> _confirmRemove(BuildContext context, String token) async {
    final l10n = context.l10n;
    final remove = await showAppDialog<bool>(
      context: context,
      builder: (context) => AppAlertDialog(
        title: Text(l10n.tagSeparatorsRemoveTitle),
        content: Text(l10n.tagSeparatorsRemoveMessage),
        actions: [
          AppDialogAction(
            isDefault: true,
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.dialogCancel),
          ),
          AppDialogAction(
            filled: true,
            isDestructive: true,
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.dialogRemove),
          ),
        ],
      ),
    );
    if (remove == true) onRemoveCustom(token);
  }

  Future<void> _openAddSheet(BuildContext context, List<String> offered) async {
    final value = await showAppBottomSheet<String>(
      context: context,
      useRootNavigator: true,
      title: context.l10n.tagSeparatorsAddTitle,
      builder: (_) => _AddDelimiterSheet(existing: offered),
    );
    if (value != null && context.mounted) onAdd(value);
  }
}

/// Equal-width cells, four to a row, in the Filters sheet's chip style.
class _ChipGrid extends StatelessWidget {
  const _ChipGrid({required this.children});

  final List<Widget> children;

  static const _gap = 8.0;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final cell = (constraints.maxWidth - 3 * _gap) / 4;
        return Wrap(
          spacing: _gap,
          runSpacing: _gap,
          children: [
            for (final child in children) SizedBox(width: cell, child: child),
          ],
        );
      },
    ),
  );
}

/// Shrinks a long delimiter like `featuring` to fit its cell.
class _ChipLabel extends StatelessWidget {
  const _ChipLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) =>
      FittedBox(fit: BoxFit.scaleDown, child: Text(text, maxLines: 1));
}

class _KeepTogetherSection extends StatefulWidget {
  const _KeepTogetherSection({
    required this.names,
    required this.onAdd,
    required this.onRemove,
  });

  final List<String> names;
  final ValueChanged<String> onAdd;
  final ValueChanged<String> onRemove;

  @override
  State<_KeepTogetherSection> createState() => _KeepTogetherSectionState();
}

class _KeepTogetherSectionState extends State<_KeepTogetherSection> {
  final _field = TextEditingController();

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _field.text.trim();
    if (name.isEmpty || _duplicate(name)) return;
    widget.onAdd(name);
    _field.clear();
    setState(() {});
  }

  bool _duplicate(String name) {
    final key = name.toLowerCase();
    return widget.names.any((n) => n.toLowerCase() == key);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final typed = _field.text.trim();
    final duplicate = typed.isNotEmpty && _duplicate(typed);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsSectionHeader(title: l10n.tagKeepTogether),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
          child: Text(
            l10n.tagKeepTogetherDescription,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        if (widget.names.isNotEmpty)
          SettingsGroup(
            children: [
              for (var i = 0; i < widget.names.length; i++)
                SettingsItem(
                  title: widget.names[i],
                  trailing: IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: l10n.tagKeepTogetherRemoveTooltip,
                    onPressed: () => widget.onRemove(widget.names[i]),
                  ),
                  showDivider: i != widget.names.length - 1,
                ),
            ],
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: TextField(
            controller: _field,
            textInputAction: TextInputAction.done,
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              hintText: l10n.tagKeepTogetherHint,
              errorText: duplicate ? l10n.tagKeepTogetherDuplicate : null,
              suffixIcon: IconButton(
                icon: const Icon(Icons.add),
                tooltip: l10n.tagKeepTogetherAdd,
                onPressed: duplicate || typed.isEmpty ? null : _submit,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Asks for one new delimiter and returns it trimmed.
class _AddDelimiterSheet extends StatefulWidget {
  const _AddDelimiterSheet({required this.existing});

  final List<String> existing;

  @override
  State<_AddDelimiterSheet> createState() => _AddDelimiterSheetState();
}

class _AddDelimiterSheetState extends State<_AddDelimiterSheet> {
  final _field = TextEditingController();

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final token = _field.text.trim();
    final valid = TagCreditSettings.isValidDelimiter(token, widget.existing);
    final duplicate =
        token.isNotEmpty &&
        !valid &&
        MetadataSeparators.validSeparator(token) == token;
    final error = token.isEmpty || valid
        ? null
        : duplicate
        ? l10n.tagSeparatorsDuplicate
        : l10n.metadataSeparatorInvalid;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _field,
            autofocus: true,
            maxLength: 16,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              hintText: l10n.tagSeparatorsAddHint,
              errorText: error,
            ),
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) {
              if (valid) Navigator.of(context).pop(token);
            },
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: valid ? () => Navigator.of(context).pop(token) : null,
            child: Text(l10n.dialogSave),
          ),
        ],
      ),
    );
  }
}

/// Picks one save-time separator; the custom field takes any 1-16 characters.
class _SeparatorPicker extends StatefulWidget {
  const _SeparatorPicker({
    required this.label,
    required this.current,
    required this.field,
    required this.rules,
  });
  final String label;
  final String current;
  final TagCreditField field;
  final TagCreditRules rules;

  @override
  State<_SeparatorPicker> createState() => _SeparatorPickerState();
}

class _SeparatorPickerState extends State<_SeparatorPicker> {
  static const _presets = ['', ', ', '; ', ' / '];
  late String? _selected = _presets.contains(widget.current)
      ? widget.current
      : null;
  late final _custom = TextEditingController(
    text: _selected == null ? widget.current : '',
  );

  @override
  void dispose() {
    _custom.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final labels = [
      context.l10n.metadataSeparatorSource,
      context.l10n.metadataSeparatorComma,
      context.l10n.metadataSeparatorSemicolon,
      context.l10n.metadataSeparatorSlash,
      context.l10n.metadataSeparatorCustom,
    ];
    final separator = _selected ?? _custom.text;
    final valid =
        _selected != null ||
        (separator.isNotEmpty &&
            MetadataSeparators.validSeparator(separator) == separator);
    final example = '${widget.label} A, ${widget.label} B';
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(0, 8, 0, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SettingsGroup(
              children: [
                for (var i = 0; i < labels.length; i++)
                  Semantics(
                    // One of a set: announce which separator is chosen.
                    selected:
                        _selected == (i < _presets.length ? _presets[i] : null),
                    inMutuallyExclusiveGroup: true,
                    child: SettingsItem(
                      title: labels[i],
                      trailing:
                          _selected ==
                              (i < _presets.length ? _presets[i] : null)
                          ? Icon(
                              Icons.check,
                              color: Theme.of(context).colorScheme.primary,
                            )
                          : const SizedBox.shrink(),
                      showDivider: i != labels.length - 1,
                      onTap: () => setState(() {
                        _selected = i < _presets.length ? _presets[i] : null;
                      }),
                    ),
                  ),
              ],
            ),
            // Same inset as the options group above, so every block lines up.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_selected == null) ...[
                    const SizedBox(height: 12),
                    // The selected row already names the field; a floating
                    // label would repeat it and collide with the group.
                    TextField(
                      controller: _custom,
                      maxLength: 16,
                      autofocus: _custom.text.isEmpty,
                      decoration: InputDecoration(
                        hintText: ' | ',
                        errorText: valid || separator.isEmpty
                            ? null
                            : context.l10n.metadataSeparatorInvalid,
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ],
                  const SizedBox(height: 16),
                  AppContentCard(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            context.l10n.metadataSeparatorPreview,
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            formatTagCreditsForSave(
                              example,
                              widget.field,
                              widget.rules,
                              valid ? separator : '',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: valid
                        ? () => Navigator.of(context).pop(separator)
                        : null,
                    child: Text(context.l10n.dialogSave),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
