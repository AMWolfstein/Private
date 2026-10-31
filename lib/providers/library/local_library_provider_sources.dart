part of 'local_library_provider.dart';

extension LocalLibrarySourceActions on LocalLibraryNotifier {
  Future<void> setSourceEnabled(String sourceId, bool enabled) async {
    final source = _current.sources
        .where((entry) => entry.id == sourceId)
        .firstOrNull;
    _sourceVersion++;
    await _db.updateSourceState(sourceId, enabled: enabled);
    await _refreshSummaryFromStorage();
    if (enabled &&
        source?.available == true &&
        source?.isIndexed == true &&
        !_scanInProgress) {
      unawaited(startSourceScan(sourceId));
    }
  }

  Future<void> removeSource(String sourceId) async {
    LocalLibrarySource? removed;
    for (final source in _current.sources) {
      if (source.id == sourceId) {
        removed = source;
        break;
      }
    }
    // Removal can run while the initial index is still loading, so it must not
    // wait for that load. The removed folder's path is only needed afterwards
    // to release its grant, so read it from storage when it is not in _current.
    if (removed == null && !_hasLoadedFromDatabase) {
      try {
        removed = (await _db.getSources())
            .where((source) => source.id == sourceId)
            .firstOrNull;
      } catch (_) {
        removed = null;
      }
    }
    final releaseUri = removed?.path;
    final stillUsed =
        releaseUri != null &&
        _current.sources.any(
          (source) => source.id != sourceId && source.path == releaseUri,
        );
    _sourceVersion++;
    await _db.removeSource(sourceId);
    await _setScanFailures(sourceId, null);
    await _refreshSummaryFromStorage();
    // Folder grants are a bounded platform resource; release the tree once no
    // remaining source refers to it.
    if (releaseUri != null &&
        releaseUri.startsWith('content://') &&
        !stillUsed) {
      try {
        await MediaFileBridge.releaseSafTree(releaseUri);
      } catch (_) {
        _log.w('Failed to release the SAF tree grant for a removed source');
      }
    }
  }

  Future<void> refreshSourceAvailability({bool scanReconnected = false}) {
    _availabilityRequestVersion++;
    _scanReconnectedOnRefresh |= scanReconnected;
    return _availabilityRefreshFuture ??= _refreshSourceAvailability()
        .whenComplete(() {
          _availabilityRefreshFuture = null;
          _scanReconnectedOnRefresh = false;
        });
  }

  Future<void> scanAllSources({bool forceFullScan = false}) async {
    final epoch = _scanEpoch;
    if (_clearingLibrary || !_ref.mounted) return;
    await _ensureLoadedFromDatabase();
    if (!_ref.mounted || _clearingLibrary || epoch != _scanEpoch) return;
    final sourceIds = _current.sources
        .where((source) => source.enabled && source.available)
        .map((source) => source.id)
        .toList(growable: false);
    await _scanSourcesSequentially(sourceIds, forceFullScan: forceFullScan);
  }
}
