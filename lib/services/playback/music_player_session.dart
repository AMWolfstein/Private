part of 'music_player_service.dart';

/// Session persistence and queue revision tracking for [MusicPlayerHandler].
extension _MusicPlayerHandlerSession on MusicPlayerHandler {
  int get _sessionQueueRevision => _sessionWriter.queueRevision;

  void _markSessionQueueChanged() => _sessionWriter.queueChanged();

  List<Map<String, dynamic>> _sessionMedia() {
    final original = _originalQueueOrder;
    final ranks = Map<MediaItem, int>.identity();
    if (original != null) {
      for (var i = 0; i < original.length; i++) {
        ranks[original[i]] = i;
      }
    }
    return [
      for (var i = 0; i < _media.length; i++)
        {
          ..._media[i].toJson(),
          'queueOriginalIndex': ranks[_queueItems[i]] ?? i,
        },
    ];
  }

  /// Persists the queue only when it changed. Periodic position updates write
  /// fixed-size scalar columns, avoiding full queue JSON serialization every
  /// ten seconds for large playback sessions.
  Future<void> _persistSession({Duration? position}) {
    if (_restoringSession) return Future<void>.value();
    if (_media.isEmpty || _index < 0 || _index >= _media.length) {
      return _sessionWriter.clear();
    }
    return _sessionWriter.persist(
      serializeQueue: _sessionMedia,
      index: _index,
      position: position ?? Duration.zero,
      shuffle: _shuffle,
      repeatMode: _repeatMode.name,
    );
  }

  Future<Duration> _currentPositionForPersist() async {
    // During restore/source preparation the engine may report a stale zero (or
    // the previous source). The broadcast position already represents the
    // intended start point for the current queue item.
    if (!_sourceReady) return playbackState.value.position;
    try {
      final position = await _player.getCurrentPosition();
      if (position != null) return position;
    } catch (_) {}
    return playbackState.value.position;
  }
}
