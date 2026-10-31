import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show ImageByteFormat, ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart' show ShareParams, SharePlus, XFile;
import 'package:sistrum/providers/library_tag_credits_provider.dart';
import 'package:sistrum/l10n/l10n.dart';
import 'package:sistrum/services/playback/stats/listening_rewind.dart';
import 'package:sistrum/services/playback/stats/listening_statistics.dart';
import 'package:sistrum/core/theme/app_tokens.dart';
import 'package:sistrum/widgets/primitives/app_action_button.dart';
import 'package:sistrum/widgets/primitives/app_bottom_sheet.dart';
import 'package:sistrum/widgets/primitives/app_content_card.dart';
import 'package:sistrum/widgets/primitives/app_loading_indicator.dart';
import 'package:sistrum/widgets/player/artwork/player_artwork.dart';
import 'package:sistrum/widgets/settings/settings_group.dart';
import 'package:sistrum/widgets/settings/settings_item_rows.dart';
import 'package:sistrum/widgets/header/header_controls.dart';

part 'listening_rewind_screen_banners.dart';
part 'listening_rewind_screen_story.dart';
part 'listening_rewind_screen_slide.dart';
part 'listening_rewind_screen_backdrop.dart';
part 'listening_rewind_screen_stats.dart';

final listeningRewindProvider = FutureProvider.autoDispose
    .family<ListeningRewind, ListeningRewindPeriod>((ref, period) async {
      await listeningRecorder.flush();
      final range = ListeningRewindRange.of(period, DateTime.now());
      final rules = ref.watch(tagCreditRulesProvider);
      return ListeningStatisticsStore.instance.read(
        (db) => readListeningRewind(
          db,
          range,
          yearly: period == ListeningRewindPeriod.year,
          rules: rules,
        ),
      );
    });

/// The Rewind the Library advertises today, or null. A window without any
/// listening is not advertised, so the banner never opens an empty story.
final listeningRewindSpotlightProvider =
    FutureProvider.autoDispose<ListeningRewindSpotlight?>((ref) async {
      final now = DateTime.now();
      final tomorrow = DateTime(now.year, now.month, now.day + 1);
      final refresh = Timer(tomorrow.difference(now), ref.invalidateSelf);
      ref.onDispose(refresh.cancel);
      final spotlight = ListeningRewindSpotlight.at(now);
      if (spotlight == null) return null;
      await listeningRecorder.flush();
      final range = ListeningRewindRange.of(spotlight.period, now);
      final rows = await ListeningStatisticsStore.instance.read(
        (db) => db.rawQuery(
          'SELECT 1 FROM listening '
          'WHERE day >= ? AND day < ? AND milliseconds > 0 LIMIT 1',
          [listeningDay(range.start), listeningDay(range.end)],
        ),
      );
      return rows.isEmpty ? null : spotlight;
    });

String listeningRewindPeriodLabel(
  BuildContext context,
  ListeningRewindPeriod period,
) => switch (period) {
  ListeningRewindPeriod.weeks => context.l10n.listeningRewindLastWeeks(4),
  ListeningRewindPeriod.quarter => context.l10n.listeningRewindLastMonths(3),
  ListeningRewindPeriod.halfYear => context.l10n.listeningRewindLastMonths(6),
  ListeningRewindPeriod.year => context.l10n.listeningRewindThisYear(
    DateTime.now().year,
  ),
};

/// Asks for a window, then plays its Rewind.
Future<void> showListeningRewind(BuildContext context) async {
  const icons = {
    ListeningRewindPeriod.weeks: Icons.today,
    ListeningRewindPeriod.quarter: Icons.date_range,
    ListeningRewindPeriod.halfYear: Icons.event_outlined,
    ListeningRewindPeriod.year: Icons.auto_awesome,
  };
  // Opened from the Library tab: the sheet and the story cover the shell
  // chrome instead of sliding beneath the tab bar and mini player.
  final period = await showAppBottomSheet<ListeningRewindPeriod>(
    context: context,
    useRootNavigator: true,
    title: context.l10n.listeningRewindChoosePeriod,
    builder: (sheetContext) => Padding(
      padding: EdgeInsets.only(bottom: sheetContext.tokens.gapLg),
      child: SettingsGroup(
        children: [
          for (final period in ListeningRewindPeriod.values)
            SettingsItem(
              icon: icons[period],
              title: listeningRewindPeriodLabel(sheetContext, period),
              showDivider: period != ListeningRewindPeriod.values.last,
              onTap: () => Navigator.pop(sheetContext, period),
            ),
        ],
      ),
    ),
  );
  if (period == null || !context.mounted) return;
  await openListeningRewind(context, period);
}

/// Plays the Rewind of [period] above the shell chrome.
Future<void> openListeningRewind(
  BuildContext context,
  ListeningRewindPeriod period,
) => Navigator.of(context, rootNavigator: true).push(
  MaterialPageRoute<void>(
    fullscreenDialog: true,
    builder: (_) => ListeningRewindScreen(period: period),
  ),
);

/// The permanent way in, on the listening statistics screen: a row that asks
/// for any window.
class ListeningRewindScreen extends ConsumerWidget {
  const ListeningRewindScreen({super.key, required this.period});

  final ListeningRewindPeriod period;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rewind = ref.watch(listeningRewindProvider(period));

    final background = Colors.black;
    final foreground = Colors.white;
    Widget message(String text) => _RewindMessage(
      text: text,
      background: background,
      foreground: foreground,
    );
    return Scaffold(
      backgroundColor: background,
      body: rewind.when(
        loading: () => Center(child: AppLoadingIndicator(color: foreground)),
        error: (_, _) => message(context.l10n.listeningRewindLoadError),
        data: (rewind) => rewind.isEmpty
            ? message(context.l10n.listeningRewindEmpty)
            : _RewindStory(rewind: rewind, period: period),
      ),
    );
  }
}
