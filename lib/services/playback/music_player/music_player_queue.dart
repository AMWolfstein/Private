part of 'music_player_service.dart';

/// Queue ordering, shuffle and enqueue bookkeeping for [MusicPlayerHandler].
extension _MusicPlayerHandlerQueue on MusicPlayerHandler {
  MediaItem _toMediaItem(
    PlayableMedia media, {
    String? resolvedSource,
    String? resolvedArtwork,
  }) => media.toMediaItem(
    resolvedSource: resolvedSource,
    resolvedArtwork: resolvedArtwork,
    unknownTitle: _runtime.unknownTitle,
    unknownArtist: _runtime.unknownArtist,
  );

  void _applyQueueOrder(List<MediaItem> order) {
    final current = _index >= 0 && _index < _queueItems.length
        ? _queueItems[_index]
        : null;
    final media = Map<MediaItem, PlayableMedia>.identity();
    for (var i = 0; i < _media.length; i++) {
      media[_queueItems[i]] = _media[i];
    }
    _queueItems
      ..clear()
      ..addAll(order);
    _media
      ..clear()
      ..addAll(order.map((item) => media[item]!));
    _index = current == null
        ? -1
        : order.indexWhere((item) => identical(item, current));
    _playHistory.clear();
    if (_index >= 0) _playHistory.record(_index);
  }

  void _shuffleQueue() {
    _originalQueueOrder ??= List.of(_queueItems);
    final manual = [
      for (var i = 0; i < _media.length; i++)
        if (i == _index || !_media[i].autoplay) i,
    ];
    final order = buildShuffledQueueOrder(
      mediaCount: manual.length,
      currentIndex: manual.indexOf(_index),
      random: _random,
    );
    _applyQueueOrder([
      ...order.map((index) => _queueItems[manual[index]]),
      for (var i = 0; i < _media.length; i++)
        if (i != _index && _media[i].autoplay) _queueItems[i],
    ]);
  }

  void _rememberEnqueued(List<MediaItem> items, {required bool playNext}) {
    final original = _originalQueueOrder;
    if (original == null) return;
    final current = _queueItems[_index];
    final at = original.indexWhere((item) => identical(item, current));
    final firstAutoplay = original.indexWhere(
      (item) => item.extras?['autoplay'] == true && !identical(item, current),
      max(0, at + 1),
    );
    original.insertAll(
      playNext && at >= 0
          ? at + 1
          : firstAutoplay >= 0
          ? firstAutoplay
          : original.length,
      items,
    );
  }
}
