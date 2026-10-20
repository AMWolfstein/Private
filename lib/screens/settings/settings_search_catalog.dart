import 'package:flutter/material.dart';
import 'package:spotiflac_android/l10n/app_localizations.dart';

/// A control or submenu that can be discovered from the root Settings search.
///
/// The catalog contains only presentation metadata. The owning settings page
/// remains responsible for reading and changing the actual setting value.
class SettingsSearchEntry {
  const SettingsSearchEntry({
    required this.icon,
    required this.title,
    this.subtitle,
    this.keywords = const [],
    String? targetLabel,
  }) : targetLabel = targetLabel ?? title;

  final IconData icon;
  final String title;
  final String? subtitle;
  final List<String> keywords;

  /// Label of the actual destination widget. Usually the result title, but a
  /// hidden or toolbar-only action may point at its nearest visible section.
  final String targetLabel;

  bool matches(SettingsSearchQuery query) =>
      query.matches([title, ?subtitle, ...keywords]);
}

/// Normalizes the query once per keystroke, rather than once for every entry.
class SettingsSearchQuery {
  SettingsSearchQuery(String value)
    : terms = value
          .trim()
          .toLowerCase()
          .split(RegExp(r'\s+'))
          .where((term) => term.isNotEmpty)
          .toList(growable: false);

  final List<String> terms;

  bool get isEmpty => terms.isEmpty;

  bool matches(Iterable<String> values) {
    if (isEmpty) return true;
    final haystack = values.join(' ').toLowerCase();
    return terms.every(haystack.contains);
  }
}

/// Localized index of controls found inside every first-level settings page.
class SettingsSearchCatalog {
  SettingsSearchCatalog(AppLocalizations l10n, {bool androidAudio = false})
    : appearance = [
        SettingsSearchEntry(
          icon: Icons.rounded_corner,
          title: l10n.appearanceGlassOutlines,
          subtitle: l10n.appearanceGlassOutlinesSubtitle,
          keywords: const [
            'mornye',
            'liquid glass',
            'border',
            'rim',
            'outline',
          ],
        ),

        SettingsSearchEntry(
          icon: Icons.color_lens_outlined,
          title: l10n.sectionColor,
          keywords: const ['palette', 'seed color', 'accent'],
        ),
        SettingsSearchEntry(
          icon: Icons.contrast,
          title: l10n.sectionTheme,
          subtitle:
              '${l10n.appearanceThemeSystem}, ${l10n.appearanceThemeLight}, '
              '${l10n.appearanceThemeDark}',
          keywords: const ['light mode', 'dark mode'],
        ),

        SettingsSearchEntry(
          icon: Icons.font_download_outlined,
          title: l10n.appearanceUseSystemFont,
          subtitle: l10n.appearanceUseSystemFontSubtitle,
          keywords: const [
            'font',
            'typeface',
            'typography',
            'system font',
            'huruf',
          ],
        ),
        SettingsSearchEntry(
          icon: Icons.animation,
          title: l10n.appearanceHeroAnimations,
          subtitle: l10n.appearanceHeroAnimationsSubtitle,
          keywords: const ['transition', 'motion'],
        ),
        SettingsSearchEntry(
          icon: Icons.blur_on,
          title: l10n.appearanceForceBlur,
          subtitle: l10n.appearanceForceBlurSubtitle,
          keywords: const ['backdrop blur', 'performance'],
        ),
        SettingsSearchEntry(
          icon: Icons.language,
          title: l10n.appearanceLanguage,
          keywords: const ['locale', 'translation'],
        ),
        SettingsSearchEntry(
          icon: Icons.grid_view_outlined,
          title: l10n.appearancePlayerView,
          subtitle:
              '${l10n.appearancePlayerViewNormal}, '
              '${l10n.appearancePlayerViewImmersive}',
          keywords: const ['player', 'normal', 'immersive', 'artwork', 'cover'],
        ),
      ],
      library = [
        SettingsSearchEntry(
          icon: Icons.library_music_outlined,
          title: l10n.libraryEnableLocalLibrary,
          subtitle: l10n.libraryEnableLocalLibrarySubtitle,
          keywords: const ['local music'],
        ),

        SettingsSearchEntry(
          icon: Icons.content_copy_outlined,
          title: l10n.libraryShowDuplicateIndicator,
          subtitle: l10n.libraryShowDuplicateIndicatorSubtitle,
          keywords: const ['duplicate badge'],
        ),
        SettingsSearchEntry(
          icon: Icons.difference_outlined,
          title: l10n.libraryReviewDuplicates,
          subtitle: l10n.libraryReviewDuplicatesSubtitle,
          keywords: const ['duplicate songs'],
        ),
        SettingsSearchEntry(
          icon: Icons.autorenew_rounded,
          title: l10n.libraryAutoScan,
          keywords: const ['automatic scan', 'daily', 'weekly'],
        ),
        SettingsSearchEntry(
          icon: Icons.refresh,
          title: l10n.libraryScan,
          subtitle: l10n.libraryScanSubtitle,
          keywords: const ['rescan', 'refresh music'],
        ),
        SettingsSearchEntry(
          icon: Icons.sync,
          title: l10n.libraryForceFullScan,
          subtitle: l10n.libraryForceFullScanSubtitle,
          keywords: const ['rescan all'],
        ),
        SettingsSearchEntry(
          icon: Icons.cleaning_services_outlined,
          title: l10n.libraryCleanupMissingFiles,
          subtitle: l10n.libraryCleanupMissingFilesSubtitle,
          keywords: const ['remove missing'],
        ),
        SettingsSearchEntry(
          icon: Icons.delete_outline,
          title: l10n.libraryClear,
          subtitle: l10n.libraryClearSubtitle,
          keywords: const ['reset local library'],
        ),
      ],
      playback = [
        SettingsSearchEntry(
          icon: Icons.playlist_play_rounded,
          title: l10n.autoplayFromLibrary,
          subtitle: l10n.autoplayDescription,
          keywords: const ['autoplay', 'queue', 'recommendation'],
        ),
        SettingsSearchEntry(
          icon: Icons.auto_awesome_outlined,
          title: l10n.autoplayPersonalization,
          subtitle: l10n.autoplayPersonalizationDescription,
          keywords: const ['machine learning', 'recommendation', 'personal'],
        ),
        SettingsSearchEntry(
          icon: Icons.insights_outlined,
          title: l10n.listeningStats,
          subtitle: l10n.listeningStatsDescription,
          keywords: const ['wrapped', 'statistics', 'listening', 'stats'],
        ),
        SettingsSearchEntry(
          icon: Icons.graphic_eq,
          title: l10n.libraryPlaybackNormalization,
          subtitle: l10n.libraryPlaybackNormalizationSubtitle,
          keywords: const ['replaygain', 'volume'],
        ),
        SettingsSearchEntry(
          icon: Icons.volume_off_outlined,
          title: l10n.playbackPauseOnMute,
          subtitle: l10n.playbackPauseOnMuteDescription,
          keywords: const ['mute', 'volume', 'pause', 'resume'],
        ),
        SettingsSearchEntry(
          icon: Icons.headphones_outlined,
          title: l10n.playbackOnHeadphonesConnected,
          subtitle: l10n.playbackOnHeadphonesConnectedDescription,
          keywords: const ['earphone', 'headphone', 'bluetooth', 'connect'],
        ),
        SettingsSearchEntry(
          icon: Icons.compare_arrows,
          title: 'AutoMix',
          subtitle: l10n.autoMixDescription,
          keywords: const [
            'crossfade',
            'beat matching',
            'duration',
            'pitch',
            'echo',
            'filter',
            'speed',
          ],
        ),
        if (androidAudio) ...[
          SettingsSearchEntry(
            icon: Icons.usb,
            title: l10n.usbBitPerfect,
            subtitle: l10n.usbBitPerfectDescription,
            keywords: const ['usb', 'dac', 'dsd', 'dop', 'hardware volume'],
          ),
          SettingsSearchEntry(
            icon: Icons.headphones,
            title: l10n.dapExclusive,
            subtitle: l10n.dapExclusiveDescription,
            keywords: const ['oboe', 'aaudio', 'exclusive', 'hi-res'],
            targetLabel: l10n.usbBitPerfect,
          ),
        ],
      ],
      lyrics = [
        SettingsSearchEntry(
          icon: Icons.light_mode_outlined,
          title: l10n.lyricsKeepScreenOn,
          subtitle: l10n.lyricsKeepScreenOnSubtitle,
          keywords: const ['screen timeout', 'awake', 'sleep', 'layar'],
        ),
      ],
      cache = [
        SettingsSearchEntry(
          icon: Icons.folder_outlined,
          title: l10n.cacheAppDirectory,
          subtitle: l10n.cacheAppDirectoryDesc,
          keywords: const ['application cache'],
        ),
        SettingsSearchEntry(
          icon: Icons.timer_outlined,
          title: l10n.cacheTempDirectory,
          subtitle: l10n.cacheTempDirectoryDesc,
          keywords: const ['temporary files'],
        ),
        SettingsSearchEntry(
          icon: Icons.image_outlined,
          title: l10n.cacheCoverImage,
          subtitle: l10n.cacheCoverImageDesc,
          keywords: const ['artwork cache'],
        ),
        SettingsSearchEntry(
          icon: Icons.library_music_outlined,
          title: l10n.cacheLibraryCover,
          subtitle: l10n.cacheLibraryCoverDesc,
          keywords: const ['local artwork cache'],
        ),
        SettingsSearchEntry(
          icon: Icons.graphic_eq_outlined,
          title: l10n.cacheAudioAnalysis,
          subtitle: l10n.cacheAudioAnalysisDesc,
          keywords: const ['spectrogram cache'],
        ),

        SettingsSearchEntry(
          icon: Icons.cleaning_services_outlined,
          title: l10n.cacheCleanupUnused,
          subtitle: l10n.cacheCleanupUnusedDesc,
          keywords: const ['clear cache', 'free space'],
        ),
        SettingsSearchEntry(
          icon: Icons.delete_sweep_outlined,
          title: l10n.cacheClearAll,
          targetLabel: l10n.cacheSectionMaintenance,
          keywords: const ['delete all cache'],
        ),
      ],
      backup = [
        SettingsSearchEntry(
          icon: Icons.ios_share,
          title: l10n.backupExportButton,
          subtitle: l10n.backupExportSectionDescription,
          keywords: const ['create backup', 'save settings'],
        ),
        SettingsSearchEntry(
          icon: Icons.settings_backup_restore,
          title: l10n.backupImportButton,
          subtitle: l10n.backupImportSectionDescription,
          keywords: const ['restore backup', 'load settings'],
        ),
      ],
      logs = [
        SettingsSearchEntry(
          icon: Icons.bug_report,
          title: l10n.optionsDetailedLogging,
          keywords: const ['debug logs', 'diagnostics'],
        ),
        SettingsSearchEntry(
          icon: Icons.filter_list,
          title: l10n.logFilterLevel,
          subtitle: l10n.logFilterBySeverity,
          targetLabel: l10n.logFilterSection,
          keywords: const ['severity', 'error warning debug'],
        ),
        SettingsSearchEntry(
          icon: Icons.search,
          title: l10n.logSearchHint,
          targetLabel: l10n.logFilterSection,
          keywords: const ['find logs'],
        ),
        SettingsSearchEntry(
          icon: Icons.copy,
          title: l10n.logCopyLogs,
          targetLabel: l10n.logFilterSection,
          keywords: const ['clipboard'],
        ),
        SettingsSearchEntry(
          icon: Icons.share,
          title: l10n.logShareLogs,
          targetLabel: l10n.logFilterSection,
          keywords: const ['export logs'],
        ),
        SettingsSearchEntry(
          icon: Icons.delete_outline,
          title: l10n.logClearLogs,
          targetLabel: l10n.logFilterSection,
          keywords: const ['delete logs'],
        ),
      ],
      about = [
        SettingsSearchEntry(
          icon: Icons.info_outline,
          title: l10n.aboutVersion,
          keywords: const ['build number', 'app version'],
        ),
      ];

  final List<SettingsSearchEntry> appearance;
  final List<SettingsSearchEntry> library;
  final List<SettingsSearchEntry> playback;
  final List<SettingsSearchEntry> lyrics;
  final List<SettingsSearchEntry> cache;
  final List<SettingsSearchEntry> backup;
  final List<SettingsSearchEntry> logs;
  final List<SettingsSearchEntry> about;
}
