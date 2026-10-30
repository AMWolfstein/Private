part of 'music_player_service.dart';

/// Local source resolution, SAF leases and output preparation for [MusicPlayerHandler].
extension _MusicPlayerHandlerSource on MusicPlayerHandler {
  Future<double> _normalizationVolumeFor(
    String path, {
    String? cacheKey,
    String? displayName,
  }) async {
    if (!_settings.playbackNormalization ||
        _settings.usbBitPerfect ||
        _player.isDirect) {
      return 1.0;
    }
    return _normalizationCache.volumeFor(
      path,
      cacheKey: cacheKey,
      displayName: displayName,
      preampDb: _settings.playbackNormalizationPreamp,
      preferAlbumGain: _settings.playbackNormalizationMode == 'album',
    );
  }

  Future<String?> _resolveSource(PlayableMedia media) async {
    if (!media.isContentUri) return media.source;
    return _sourceCache.resolve(media.source);
  }

  Future<void> _cleanupPendingResolvedPaths() => _sourceCache.releaseUnpinned();

  Future<ContentUriPlaybackLease?> _openPlaybackLease(
    PlayableMedia media,
  ) async {
    if (!_dependencies.isAndroid || !media.isContentUri) return null;
    try {
      return await MediaFileBridge.openContentUriPlaybackLease(media.source);
    } catch (e) {
      _log.w('Failed to open direct SAF playback lease: $e');
      return null;
    }
  }

  Future<void> _releaseLease(ContentUriPlaybackLease? lease) async {
    if (lease != null) {
      await MediaFileBridge.closeContentUriPlaybackLease(lease.token);
    }
  }

  /// Applies gain, audio focus and the audio context before the source starts.
  /// Returns false when a newer request has taken over.
  Future<bool> _prepareOutput(
    double normalizationVolume,
    bool Function() isCurrent,
  ) async {
    await _player.setAudioContext(musicAudioContext);
    if (!isCurrent()) return false;
    await _activateAudioSession();
    if (!isCurrent()) return false;
    await _player.stop();
    _sourceReady = false;
    if (!isCurrent()) return false;
    await _player.setVolume(normalizationVolume);
    _normalizationVolume = normalizationVolume;
    return isCurrent();
  }
}
