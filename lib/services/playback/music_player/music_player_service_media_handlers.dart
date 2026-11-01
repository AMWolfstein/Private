part of 'music_player_service.dart';

extension _MusicPlayerHandlerDelegates2 on MusicPlayerHandler {
  Future<void> _skipToPreviousImpl() async {
    await _autoMix.cancel();
    if (playbackState.value.position > const Duration(seconds: 3)) {
      await seek(Duration.zero);
      return;
    }
    if (_shuffle) {
      if (_playHistory.length >= 2) {
        _playHistory.removeLast();
        final prev = _playHistory.last;
        await _playIndex(prev, recordHistory: false, userSkip: true);
      } else {
        await seek(Duration.zero);
      }
      return;
    }
    if (_index > 0) await _playIndex(_index - 1, userSkip: true);
  }

  Future<void> _skipToQueueItemImpl(int index) =>
      _playIndex(index, userSkip: true);

  Future<List<MediaItem>> _getChildrenImpl(
    String parentMediaId, [
    Map<String, dynamic>? options,
  ]) async {
    if (parentMediaId == AudioService.recentRootId) {
      await _runtime.restoreSession();
      final item = mediaItem.value;
      return item == null ? const [] : [await _runtime.browser.present(item)];
    }
    return _runtime.browser.children(parentMediaId, options);
  }

  Future<MediaItem?> _getMediaItemImpl(String mediaId) async {
    final index = _media.indexWhere((m) => m.id == mediaId);
    return index < 0
        ? _runtime.browser.item(mediaId)
        : _runtime.browser.present(_queueItems[index]);
  }

  Future<void> _playFromMediaIdImpl(
    String mediaId, [
    Map<String, dynamic>? extras,
  ]) async {
    if (!MediaLibraryBrowser.isBrowserId(mediaId)) {
      final index = _media.indexWhere((m) => m.id == mediaId);
      if (index >= 0) await _playIndex(index);
      return;
    }
    await _resolveBrowserQueue(
      (current) => _runtime.browser.queueFor(mediaId, current: current),
    );
  }

  Future<void> _playFromSearchImpl(
    String query, [
    Map<String, dynamic>? extras,
  ]) async {
    // Empty assistant requests resume a session; structured media focus still
    // selects the named album/artist rather than ignoring that request.
    if (MediaLibraryBrowser.searchText(query, extras).isEmpty) {
      await _runtime.restoreSession();
      if (_media.isNotEmpty) return play();
    }
    await _resolveBrowserQueue(
      (current) => _runtime.browser.queueForSearch(query, extras, current),
    );
  }

  Future<void> _resolveBrowserQueue(
    Future<BrowserQueue?> Function(bool Function()) resolve,
  ) async {
    final request = ++_browserRequestGeneration;
    final playback = _playRequestGeneration;
    final revision = _sessionQueueRevision;
    bool current() =>
        !_disposed &&
        request == _browserRequestGeneration &&
        playback == _playRequestGeneration &&
        revision == _sessionQueueRevision;
    final result = await resolve(current);
    if (result == null || result.items.isEmpty || !current()) return;
    // No await between the final ownership check and publishing this queue.
    _shuffle = result.shuffle;
    await _setQueueAndPlayImpl(result.items, initialIndex: result.index);
  }

  Future<void> _playMediaItemImpl(MediaItem mediaItem) =>
      playFromMediaId(mediaItem.id);

  Future<void> _onSourceDeletedImpl(String source) async {
    final target = source.trim();
    if (_disposed || target.isEmpty) return;

    final hadPendingResolution = await _sourceCache.invalidate(target);

    final wasCurrent =
        _index >= 0 &&
        _index < _media.length &&
        _media[_index].source == target;

    var removedBeforeCurrent = 0;
    final kept = <PlayableMedia>[];
    final keptQueue = <MediaItem>[];
    for (var i = 0; i < _media.length; i++) {
      if (_media[i].source == target) {
        if (i < _index) removedBeforeCurrent++;
        continue;
      }
      kept.add(_media[i]);
      keptQueue.add(_queueItems[i]);
    }

    if (kept.length == _media.length) return;

    _media
      ..clear()
      ..addAll(kept);
    _queueItems
      ..clear()
      ..addAll(keptQueue);
    final keptSet = Set<MediaItem>.identity()..addAll(keptQueue);
    _originalQueueOrder?.removeWhere((item) => !keptSet.contains(item));
    _markSessionQueueChanged();
    _playHistory.clear();
    queue.add(List<MediaItem>.unmodifiable(_queueItems));

    Future<void>? reaction;
    if (_media.isEmpty) {
      reaction = stop();
    } else if (wasCurrent) {
      final nextIndex = _index.clamp(0, _media.length - 1);
      reaction = _playIndex(nextIndex);
    } else if (_index >= 0) {
      _index = (_index - removedBeforeCurrent).clamp(0, _media.length - 1);
      _broadcastState();
      unawaited(_persistSession(position: playbackState.value.position));
    }
    if (!hadPendingResolution) {
      await reaction;
    } else {
      // Queue invalidation must not wait behind an unavailable SAF provider.
      unawaited(
        reaction?.catchError((Object error) {
          _log.w('Could not update playback after source deletion: $error');
        }),
      );
    }
  }

  Future<void> _disposeImpl() => _disposeFuture ??= _dispose();
}
