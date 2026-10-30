import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sistrum/l10n/l10n.dart';
import 'package:sistrum/models/tag_split_settings.dart';
import 'package:sistrum/providers/settings_provider.dart';
import 'package:sistrum/screens/settings/metadata_separator_settings_page.dart';
import 'package:sistrum/utils/nav_bar_inset.dart';
import 'package:sistrum/widgets/primitives/app_content_card.dart';
import 'package:sistrum/widgets/primitives/app_sliver_header.dart';
import 'package:sistrum/widgets/settings/settings_group.dart';
import 'package:sistrum/widgets/settings/settings_item_rows.dart';

/// One named set of delimiters, applied in one tap.
typedef _Preset = ({String Function(BuildContext) label, List<String> tokens});

/// Splits names in artist, composer and genre tags, then sets how tags are saved.
class TagSeparatorSettingsPage extends ConsumerWidget {
  const TagSeparatorSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final split = ref.watch(settingsProvider.select((s) => s.tagSplit));
    final notifier = ref.read(settingsProvider.notifier);
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          AppSliverHeader.page(title: context.l10n.metadataSeparators),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
              child: Text(context.l10n.tagSplitDescription),
            ),
          ),
          SliverToBoxAdapter(
            child: SettingsGroup(
              children: [
                SettingsSwitchItem(
                  icon: Icons.call_split,
                  title: context.l10n.tagSplitEnable,
                  subtitle: context.l10n.tagSplitEnableDescription,
                  value: split.enabled,
                  onChanged: notifier.setTagSplitEnabled,
                  showDivider: false,
                ),
              ],
            ),
          ),
          SliverToBoxAdapter(
            child: _DelimiterSection(
              title: context.l10n.tagSplitArtists,
              enabled: split.enabled,
              delimiters: split.artistDelimiters,
              defaults: kArtistDelimiters,
              baseTokens: _artistBase,
              presets: _artistPresets,
              examples: _artistExamples,
              onChanged: notifier.setTagSplitArtistDelimiters,
            ),
          ),
          SliverToBoxAdapter(
            child: _DelimiterSection(
              title: context.l10n.tagSplitGenres,
              enabled: split.enabled,
              delimiters: split.genreDelimiters,
              defaults: kGenreDelimiters,
              baseTokens: _genreBase,
              presets: _genrePresets,
              examples: _genreExamples,
              onChanged: notifier.setTagSplitGenreDelimiters,
            ),
          ),
          SliverToBoxAdapter(
            child: SettingsSectionHeader(title: context.l10n.tagSplitSaving),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text(context.l10n.metadataSeparatorsDescription),
            ),
          ),
          const SliverToBoxAdapter(child: MetadataSeparatorRows()),
          const SliverToBoxAdapter(child: SizedBox(height: 32)),
          const NavBarSliverSpacer(),
        ],
      ),
    );
  }
}

const _artistBase = ['/', ';', ',', '+', '&', '،'];

const _genreBase = [';', '،', ',', '/', '&'];

final _artistPresets = <_Preset>[
  (label: (c) => c.l10n.tagSplitPresetAll, tokens: kArtistDelimiters),
  (label: (c) => c.l10n.tagSplitPresetStandard, tokens: const [';', '/']),
  (label: (c) => c.l10n.tagSplitPresetMinimal, tokens: const [';']),
  (
    label: (c) => c.l10n.tagSplitPresetFeatured,
    tokens: const [';', '/', 'feat.', 'ft.', 'featuring'],
  ),
  (
    label: (c) => c.l10n.tagSplitPresetExtended,
    tokens: const [';', '/', ',', '+', '&'],
  ),
  (label: (c) => c.l10n.tagSplitPresetCjk, tokens: const ['、', '／', '・', '•']),
  (label: (c) => c.l10n.tagSplitPresetArabic, tokens: const ['،', ';', '/']),
];

final _genrePresets = <_Preset>[
  (label: (c) => c.l10n.tagSplitPresetGenreDefault, tokens: kGenreDelimiters),
  (label: (c) => c.l10n.tagSplitPresetMinimal, tokens: const [';']),
];

const _artistExamples = [
  'Kendrick Lamar; SZA',
  'AC\\/DC',
  'Tyler, The Creator',
  'Simon & Garfunkel',
  'Daft Punk feat. Pharrell Williams',
  'عمرو دياب، تامر حسني',
];

const _genreExamples = ['Soundtrack; Hip-Hop/Rap', 'R&B/Soul', 'Pop، Rock'];

/// Presets, delimiter chips and a live preview for one tag kind.
class _DelimiterSection extends StatefulWidget {
  const _DelimiterSection({
    required this.title,
    required this.enabled,
    required this.delimiters,
    required this.defaults,
    required this.baseTokens,
    required this.presets,
    required this.examples,
    required this.onChanged,
  });

  final String title;
  final bool enabled;
  final List<String> delimiters;
  final List<String> defaults;
  final List<String> baseTokens;
  final List<_Preset> presets;
  final List<String> examples;
  final ValueChanged<List<String>> onChanged;

  @override
  State<_DelimiterSection> createState() => _DelimiterSectionState();
}

class _DelimiterSectionState extends State<_DelimiterSection> {
  final _custom = TextEditingController();

  @override
  void dispose() {
    _custom.dispose();
    super.dispose();
  }

  void _toggle(String token) {
    final next = widget.delimiters.contains(token)
        ? widget.delimiters.where((t) => t != token).toList()
        : [...widget.delimiters, token];
    // Never leave the list empty: an empty list would silently stop splitting.
    if (next.isEmpty) return;
    widget.onChanged(next);
  }

  void _addCustom() {
    final token = _custom.text.trim();
    if (token.isEmpty || widget.delimiters.contains(token)) return;
    _custom.clear();
    widget.onChanged([...widget.delimiters, token]);
  }

  bool _sameSet(List<String> a, List<String> b) =>
      a.length == b.length && a.every(b.contains);

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final custom = widget.delimiters
        .where(
          (t) => !widget.baseTokens.contains(t) && !widget.defaults.contains(t),
        )
        .toList();
    final chips = [
      ...widget.baseTokens,
      ...widget.defaults.where((t) => !widget.baseTokens.contains(t)),
      ...custom,
    ];
    return IgnorePointer(
      ignoring: !widget.enabled,
      child: Opacity(
        opacity: widget.enabled ? 1 : 0.45,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SettingsSectionHeader(title: widget.title),
            SettingsGroup(
              children: [
                for (var i = 0; i < widget.presets.length; i++)
                  SettingsItem(
                    title: widget.presets[i].label(context),
                    subtitle: widget.presets[i].tokens.join('  '),
                    trailing:
                        _sameSet(widget.presets[i].tokens, widget.delimiters)
                        ? Icon(Icons.check, color: colors.primary)
                        : const SizedBox.shrink(),
                    showDivider: i != widget.presets.length - 1,
                    onTap: () => widget.onChanged(widget.presets[i].tokens),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
              child: Text(
                context.l10n.tagSplitDelimiters,
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final token in chips)
                    FilterChip(
                      label: Text(token),
                      selected: widget.delimiters.contains(token),
                      onSelected: (_) => _toggle(token),
                      onDeleted: custom.contains(token)
                          ? () => widget.onChanged(
                              widget.delimiters
                                  .where((t) => t != token)
                                  .toList(),
                            )
                          : null,
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
              child: TextField(
                controller: _custom,
                maxLength: 16,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _addCustom(),
                decoration: InputDecoration(
                  labelText: context.l10n.tagSplitCustomHint,
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.add),
                    tooltip: context.l10n.tagSplitAdd,
                    onPressed: _addCustom,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
              child: AppContentCard(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.l10n.tagSplitPreview,
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      const SizedBox(height: 8),
                      for (final example in widget.examples)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Text('$example  →  ${_preview(example)}'),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _preview(String example) {
    final tokens = widget.delimiters;
    final names = splitTagNames(example, tokens);
    return names.join('  ·  ');
  }
}
