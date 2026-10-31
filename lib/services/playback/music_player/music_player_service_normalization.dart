part of 'music_player_service.dart';

extension MusicPlayerHandlerPart2 on MusicPlayerHandler {
  /// Re-applies normalization to the playing track when the setting flips.
  void reapplyNormalization() {
    final index = _index;
    final generation = _playRequestGeneration;
    final normalizationGeneration = ++_normalizationGeneration;
    if (index < 0 || index >= _media.length) return;
    unawaited(() async {
      await _autoMix.cancel();
      if (generation != _playRequestGeneration ||
          index != _index ||
          index >= _media.length ||
          _disposed) {
        return;
      }
      final media = _media[index];
      var resolved = media.isContentUri
          ? _sourceCache.cachedPath(media.source)
          : media.source;
      ContentUriPlaybackLease? playbackLease;
      if (resolved == null && media.isContentUri) {
        try {
          playbackLease = await MediaFileBridge.openContentUriPlaybackLease(
            media.source,
          );
          resolved = playbackLease?.path;
        } catch (_) {}
        resolved ??= await _resolveSource(media);
      }
      if (resolved == null) return;
      final volume = await _normalizationVolumeFor(
        resolved,
        cacheKey: media.isContentUri ? media.source : null,
        displayName: playbackLease?.displayName,
      );
      if (playbackLease != null) {
        await MediaFileBridge.closeContentUriPlaybackLease(playbackLease.token);
      }
      if (_index != index ||
          generation != _playRequestGeneration ||
          normalizationGeneration != _normalizationGeneration) {
        return;
      }
      try {
        await _player.setVolume(volume);
        _normalizationVolume = volume;
      } catch (e) {
        _log.w('Failed to apply normalization volume: $e');
      }
    }());
  }
}
