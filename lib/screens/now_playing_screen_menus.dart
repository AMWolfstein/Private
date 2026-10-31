part of 'now_playing_screen.dart';

extension _NowPlayingMenus on _NowPlayingScreenState {
  Future<void> _showLyricsOptions(
    BuildContext buttonContext, {
    required bool pronunciation,
    required bool translation,
  }) async {
    final settings = ref.read(settingsProvider);
    final l10n = context.l10n;
    final actions = <(String, String, IconData)>[
      if (pronunciation)
        (
          'pronunciation',
          settings.playerShowPronunciation
              ? l10n.nowPlayingHidePronunciation
              : l10n.nowPlayingShowPronunciation,
          settings.playerShowPronunciation
              ? Icons.voice_over_off_outlined
              : Icons.record_voice_over_outlined,
        ),
      if (translation)
        (
          'translation',
          settings.playerShowTranslation
              ? l10n.nowPlayingHideTranslation
              : l10n.nowPlayingShowTranslation,
          Icons.translate_rounded,
        ),
    ];
    _lyricsIdleTimer?.cancel();
    _rebuild(() => _lyricsOptionsOpen = true);
    try {
      final anchor = appMenuAnchor(buttonContext);
      var menuWidth = 240.0;
      for (final (_, label, _) in actions) {
        final painter = TextPainter(
          text: TextSpan(
            text: label,
            style: Theme.of(
              context,
            ).textTheme.bodyLarge?.copyWith(fontSize: 15),
          ),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout();
        if (painter.width + 80 > menuWidth) menuWidth = painter.width + 80;
        painter.dispose();
      }
      final action = await showAppContextMenu<String>(
        context: buttonContext,
        anchor: anchor,
        preferAbove: true,
        maxWidth: menuWidth,
        builder: (menuContext) => AppContextMenu(
          dense: true,
          groups: [
            [
              for (final (value, label, icon) in actions)
                AppMenuAction(
                  icon: icon,
                  label: label,
                  onPressed: () => Navigator.of(menuContext).pop(value),
                ),
            ],
          ],
        ),
      );
      if (!mounted) return;
      final notifier = ref.read(settingsProvider.notifier);
      if (action == 'pronunciation') {
        notifier.setPlayerShowPronunciation(!settings.playerShowPronunciation);
      } else if (action == 'translation') {
        notifier.setPlayerShowTranslation(!settings.playerShowTranslation);
      }
    } finally {
      if (mounted) {
        _rebuild(() => _lyricsOptionsOpen = false);
        _scheduleLyricsControlsHide();
      }
    }
  }

  Future<void> _showTrackNavigationMenu(
    BuildContext titleContext,
    MediaItem mediaItem,
  ) async {
    final action = await showAppContextMenu<String>(
      context: titleContext,
      preferAbove: true,
      maxWidth: 280,
      builder: (_) => AppPlayerNavigationMenu(mediaItem: mediaItem),
    );
    if (!mounted) return;
    if (action == 'album') {
      await _goToCurrentAlbum(mediaItem: mediaItem);
    } else if (action == 'artist') {
      await _goToCurrentArtist(mediaItem);
    }
  }

  Future<void> _goToCurrentArtist(MediaItem mediaItem) async {
    await navigateToArtistCredits(
      context,
      artistNames: mediaItem.artist ?? '',
      rules: ref.read(tagCreditRulesProvider),
    );
  }

  Future<void> _updatePlayerCollection(
    MediaItem item, {
    required bool favorite,
  }) async {
    try {
      final provider = playerCollectionTrackProvider(item);
      if (ref.read(provider).hasError) ref.invalidate(provider);
      final track = await ref.read(provider.future);
      if (!mounted) return;
      if (favorite) {
        await ref.read(libraryCollectionsProvider.notifier).toggleLoved(track);
      } else {
        await showAddTrackToPlaylistSheet(context, ref, track);
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.l10n.snackbarError(context.friendlyError(error)),
          ),
        ),
      );
    }
  }

  Future<void> _showMoreActions({
    required BuildContext context,
    required MediaItem mediaItem,
    required String source,
    required ColorScheme colorScheme,
    Rect? anchor,
  }) async {
    final controller = ref.read(musicPlayerControllerProvider);
    final sleepTimerEndsAt = controller.sleepTimerEndsAt;
    final sleepTimerSubtitle = sleepTimerEndsAt == null
        ? null
        : context.l10n.nowPlayingSleepTimerActive(
            MaterialLocalizations.of(
              context,
            ).formatTimeOfDay(TimeOfDay.fromDateTime(sleepTimerEndsAt)),
          );
    final action = await showAppContextMenu<String>(
      context: context,
      anchor: anchor,
      preferAbove: true,
      maxWidth: 280,
      builder: (_) => AppPlayerActionsSheet(
        mediaItem: mediaItem,
        sleepTimerSubtitle: sleepTimerSubtitle,
      ),
    );
    if (!mounted || !context.mounted) return;
    switch (action) {
      case 'favorite':
        await _updatePlayerCollection(mediaItem, favorite: true);
        break;
      case 'playlist':
        await _updatePlayerCollection(mediaItem, favorite: false);
        break;
      case 'artist':
        await _goToCurrentArtist(mediaItem);
        break;
      case 'share':
        await SharePlus.instance.share(
          ShareParams(
            text: '${mediaItem.title} — ${mediaItem.artist ?? ''}',
            sharePositionOrigin:
                anchor ??
                Rect.fromCenter(
                  center: MediaQuery.sizeOf(context).center(Offset.zero),
                  width: 1,
                  height: 1,
                ),
          ),
        );
        break;
      case 'album':
        await _goToCurrentAlbum(mediaItem: mediaItem);
        break;
      case 'shareLyrics':
        await _shareLyrics();
        break;
      case 'details':
        unawaited(
          showPlayerDetailsSheet(
            context,
            colorScheme,
            metadata: _trackMetadata,
            mediaItem: ref.read(currentMediaItemProvider).value,
          ),
        );
        break;
      case 'equalizer':
        await Navigator.of(context).push<void>(
          MaterialPageRoute(builder: (_) => const EqualizerScreen()),
        );
        break;
      case 'sleepTimer':
        await _showSleepTimerSheet(context, controller, colorScheme);
        break;
    }
  }

  Future<void> _showSleepTimerSheet(
    BuildContext context,
    MusicPlayerController controller,
    ColorScheme colorScheme,
  ) async {
    const durations = [15, 30, 45, 60];
    final isActive = controller.sleepTimerEndsAt != null;
    final selection = await showAppBottomSheet<String>(
      context: context,
      useRootNavigator: true,
      backgroundColor: colorScheme.surfaceContainerHigh,
      title: context.l10n.nowPlayingSleepTimer,
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: SettingsGroup(
          children: [
            for (final minutes in durations)
              SettingsItem(
                icon: Icons.timer_outlined,
                title: sheetContext.l10n.nowPlayingSleepTimerMinutes(minutes),
                showDivider: isActive || minutes != durations.last,
                onTap: () => Navigator.of(sheetContext).pop('$minutes'),
              ),
            if (isActive)
              SettingsItem(
                icon: Icons.timer_off_outlined,
                title: sheetContext.l10n.nowPlayingSleepTimerOff,
                showDivider: false,
                onTap: () => Navigator.of(sheetContext).pop('off'),
              ),
          ],
        ),
      ),
    );
    if (!mounted || !context.mounted || selection == null) return;

    if (selection == 'off') {
      controller.cancelSleepTimer();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.nowPlayingSleepTimerCancelled)),
      );
      return;
    }

    final minutes = int.tryParse(selection);
    if (minutes == null) return;
    controller.setSleepTimer(Duration(minutes: minutes));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          context.l10n.nowPlayingSleepTimerSet(
            context.l10n.nowPlayingSleepTimerMinutes(minutes),
          ),
        ),
      ),
    );
  }

  Future<void> _goToCurrentAlbum({required MediaItem mediaItem}) async {
    final albumName = (mediaItem.album ?? '').trim();
    if (albumName.isEmpty) return;

    try {
      final album = await ref
          .read(musicPlayerControllerProvider)
          .localAlbumFor(mediaItem.id);
      if (!mounted) return;
      if (album != null) {
        final (:item, :tracks) = album;
        final albumArtist = (item.albumArtist ?? '').trim();
        pushViaPreferredNavigator(
          context,
          (_) => LocalAlbumScreen(
            albumName: item.albumName,
            artistName: albumArtist.isNotEmpty ? albumArtist : item.artistName,
            coverPath: item.coverPath,
            tracks: tracks,
          ),
        );
        return;
      }
    } catch (e) {
      _log.w('Failed to resolve local album: $e');
    }

    if (!mounted) return;
    await navigateToAlbum(
      context,
      database: ref.read(libraryDatabaseProvider),
      albumName: albumName,
      artistName: mediaItem.artist,
      coverUrl: mediaItem.artUri?.toString(),
    );
  }

  void _showQueueSheet(ColorScheme colorScheme) {
    {
      _setAppPage(2);
      return;
    }
  }
}
