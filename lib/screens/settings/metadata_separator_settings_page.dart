import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sistrum/l10n/l10n.dart';
import 'package:sistrum/models/metadata_separators.dart';
import 'package:sistrum/providers/settings_provider.dart';
import 'package:sistrum/widgets/primitives/app_bottom_sheet.dart';
import 'package:sistrum/widgets/primitives/app_content_card.dart';
import 'package:sistrum/widgets/settings/settings_group.dart';
import 'package:sistrum/widgets/settings/settings_item_rows.dart';

/// Per-field separators applied when local tags are saved from Edit Metadata.
/// Shown inside the Tag separators page.
class MetadataSeparatorRows extends ConsumerWidget {
  const MetadataSeparatorRows({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final separators = ref.watch(
      settingsProvider.select((s) => s.metadataSeparators),
    );
    final labels = {
      'artist': context.l10n.editMetadataFieldArtist,
      'album_artist': context.l10n.editMetadataFieldAlbumArtist,
      'composer': context.l10n.editMetadataFieldComposer,
      'genre': context.l10n.editMetadataFieldGenre,
    };
    return SettingsGroup(
      children: [
        for (final field in MetadataSeparators.fields)
          SettingsItem(
            icon: field == 'genre'
                ? Icons.category_outlined
                : Icons.people_alt_outlined,
            title: labels[field]!,
            subtitle: separators.toJson()[field]!.isEmpty
                ? context.l10n.metadataSeparatorSource
                : formatMetadataTagValue(
                    '${labels[field]} A, ${labels[field]} B',
                    separators.toJson()[field]!,
                  ),
            showDivider: field != MetadataSeparators.fields.last,
            onTap: () async {
              final value = await showAppBottomSheet<String>(
                context: context,
                useRootNavigator: true,
                title: labels[field]!,
                builder: (_) => _SeparatorPicker(
                  label: labels[field]!,
                  current: separators.toJson()[field]!,
                ),
              );
              if (value != null && context.mounted) {
                ref
                    .read(settingsProvider.notifier)
                    .setMetadataSeparator(field, value);
              }
            },
          ),
      ],
    );
  }
}

class _SeparatorPicker extends StatefulWidget {
  const _SeparatorPicker({required this.label, required this.current});
  final String label;
  final String current;

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
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_selected == null)
                    TextField(
                      controller: _custom,
                      maxLength: 16,
                      decoration: InputDecoration(
                        labelText: context.l10n.metadataSeparatorCustom,
                        errorText: valid || separator.isEmpty
                            ? null
                            : context.l10n.metadataSeparatorInvalid,
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
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
                            formatMetadataTagValue(
                              example,
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
