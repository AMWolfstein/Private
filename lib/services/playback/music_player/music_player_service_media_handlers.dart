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
    if (parentMediaId == AudioService.browsableRootId ||
        parentMediaId == AudioService.recentRootId) {
      return List<MediaItem>.unmodifiable(_queueItems);
    }
    return const [];
  }

  Future<MediaItem?> _getMediaItemImpl(String mediaId) async {
    final index = _media.indexWhere((m) => m.id == mediaId);
    if (index < 0) return null;
    return _queueItems[index];
  }

  Future<void> _playFromMediaIdImpl(
    String mediaId, [
    Map<String, dynamic>? extras,
  ]) async {
    final index = _media.indexWhere((m) => m.id == mediaId);
    if (index >= 0) await _playIndex(index);
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
