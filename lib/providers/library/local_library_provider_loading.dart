part of 'local_library_provider.dart';

extension _LocalLibraryLoading on LocalLibraryNotifier {
  Future<void> _ensureLoadedFromDatabase() {
    if (_hasLoadedFromDatabase) {
      return Future<void>.value();
    }
    return _loadFuture ??= _loadFromDatabase();
  }

  Future<void> _loadFromDatabase() async {
    if (_hasLoadedFromDatabase) return;
    if (_isLoaded) {
      return _loadFuture ?? Future<void>.value();
    }
    _isLoaded = true;
    final scanEpoch = _scanEpoch;
    _current = _current.copyWith(isLoading: true, loadFailed: false);

    try {
      await _recoverInterruptedScan();
      if (!_ref.mounted) return;
      // Folder configuration is independent of the potentially expensive
      // track index and storage probes. Publish it before either can fail.
      final configuredSources = await _db.getSources();
      if (!_ref.mounted) return;
      _current = _current.copyWith(sources: configuredSources);
      await _ref.read(settingsProvider.notifier).ensureLoaded();
      final reconnectedSources = await _refreshSourceAvailabilityInDatabase();
      while (_ref.mounted) {
        final sourceVersion = _sourceVersion;
        final sources = await _db.getSources();
        if (!_ref.mounted) return;
        if (sourceVersion != _sourceVersion) continue;
        _current = _current.copyWith(sources: sources);
        final count = await _db.getCount();

        DateTime? lastScannedAt;
        var scanFailures = const <String, LibraryScanFailures>{};
        try {
          final prefs = await _preferences();
          lastScannedAt = readLocalLibraryLastScannedAt(prefs);
          scanFailures = readLocalLibraryScanFailures(prefs);
        } catch (e) {
          _log.w('Failed to load lastScannedAt: $e');
        }

        if (!_ref.mounted) return;
        if (sourceVersion != _sourceVersion) {
          if (_hasLoadedFromDatabase) break;
          continue;
        }
        _current = _current.copyWith(
          totalCount: count,
          loadedIndexVersion: _current.loadedIndexVersion + 1,
          lastScannedAt: lastScannedAt,
          scanFailures: scanFailures,
          sources: sources,
        );
        _log.i(
          'Loaded local library summary: $count items, lastScannedAt: '
          '$lastScannedAt',
        );
        _hasLoadedFromDatabase = true;
        break;
      }
      if (_ref.mounted &&
          !_clearingLibrary &&
          scanEpoch == _scanEpoch &&
          reconnectedSources.reconnected.isNotEmpty) {
        unawaited(
          Future<void>.microtask(
            () => _scanSourcesSequentially(reconnectedSources.reconnected),
          ),
        );
      }
    } catch (e, stack) {
      _isLoaded = false;
      if (_ref.mounted) _current = _current.copyWith(loadFailed: true);
      _log.e('Failed to load library from database: $e', e, stack);
    } finally {
      _loadFuture = null;
      if (_ref.mounted) _current = _current.copyWith(isLoading: false);
    }
  }

  String _newSourceId(String path) {
    const offset = 0xcbf29ce484222325;
    const prime = 0x100000001b3;
    const mask = 0xffffffffffffffff;
    var hash = offset;
    for (final unit in path.codeUnits) {
      hash = ((hash ^ unit) * prime) & mask;
    }
    return 'source_${hash.toRadixString(16).padLeft(16, '0')}';
  }

  Future<void> _refreshSourceAvailability() async {
    final scanEpoch = _scanEpoch;
    await _ensureLoadedFromDatabase();
    final reconnected = <String>{};
    while (_ref.mounted) {
      final result = await _refreshSourceAvailabilityInDatabase();
      if (!_ref.mounted) return;
      reconnected.addAll(result.reconnected);
      if (result.changed) await _refreshSummaryFromStorage();
      if (result.requestVersion == _availabilityRequestVersion) break;
    }

    // Existing rows become visible as soon as availability flips. The
    // incremental pass then verifies changes made while storage was detached
    // without re-reading metadata for unchanged files.
    if (_ref.mounted &&
        !_clearingLibrary &&
        scanEpoch == _scanEpoch &&
        _scanReconnectedOnRefresh &&
        reconnected.isNotEmpty) {
      _pendingReconnectScans.addAll(reconnected);
      unawaited(_drainReconnectScans());
    }
  }

  Future<void> _scanSourcesSequentially(
    Iterable<String> sourceIds, {
    bool forceFullScan = false,
  }) async {
    final epoch = _scanEpoch;
    for (final sourceId in sourceIds) {
      if (!_ref.mounted || _clearingLibrary || epoch != _scanEpoch) break;
      await startSourceScan(sourceId, forceFullScan: forceFullScan);
      if (_scanCancelRequested) break;
    }
  }

  Future<LocalLibrarySource?> _sourceForScan(String sourceId) async {
    if (!_ref.mounted) return null;
    await _ensureLoadedFromDatabase();
    if (!_ref.mounted) return null;
    while (_ref.mounted) {
      final sourceVersion = _sourceVersion;
      final source = (await _db.getSources())
          .where((entry) => entry.id == sourceId)
          .firstOrNull;
      if (!_ref.mounted) return null;
      if (sourceVersion != _sourceVersion) continue;
      return source?.enabled == true && source?.available == true
          ? source
          : null;
    }
    return null;
  }

  Future<void> _drainReconnectScans() async {
    if (_drainingReconnectScans || !_ref.mounted || _clearingLibrary) return;
    _drainingReconnectScans = true;
    try {
      while (_ref.mounted &&
          !_clearingLibrary &&
          _pendingReconnectScans.isNotEmpty) {
        final active = _scanCompletion;
        if (active != null) await active;
        if (!_ref.mounted || _pendingReconnectScans.isEmpty) break;
        final sourceId = _pendingReconnectScans.first;
        await startSourceScan(sourceId);
        _pendingReconnectScans.remove(sourceId);
      }
    } catch (error, stack) {
      _log.e('Failed to scan reconnected library source: $error', error, stack);
    } finally {
      _drainingReconnectScans = false;
    }
  }

  Future<void> _refreshSummaryFromStorage({DateTime? lastScannedAt}) async {
    final sourceVersion = ++_sourceVersion;
    final sources = await _db.getSources();
    if (!_ref.mounted || sourceVersion != _sourceVersion) return;
    _current = _current.copyWith(sources: sources);
    final count = await _db.getCount();
    if (!_ref.mounted || sourceVersion != _sourceVersion) return;
    final latestSourceScan = sources
        .map((source) => source.lastScannedAt)
        .whereType<DateTime>()
        .fold<DateTime?>(
          null,
          (latest, value) =>
              latest == null || value.isAfter(latest) ? value : latest,
        );
    _current = _current.copyWith(
      loadFailed: false,
      totalCount: count,
      loadedIndexVersion: _current.loadedIndexVersion + 1,
      lastScannedAt: lastScannedAt ?? latestSourceScan,
      sources: sources,
    );
    _hasLoadedFromDatabase = true;
    _isLoaded = true;
  }

  String _displayNameForPath(String path) {
    if (path.startsWith('content://')) {
      try {
        // `pathSegments` already percent-decodes each segment; decoding again
        // would turn a literal `%XX` in a folder name into a different name.
        final decoded = Uri.parse(path).pathSegments.last;
        final relative = decoded.contains(':')
            ? decoded.substring(decoded.indexOf(':') + 1)
            : decoded;
        if (relative.trim().isNotEmpty) {
          return relative.split('/').last;
        }
      } catch (_) {}
      return 'Music';
    }
    final normalized = path
        .replaceAll('\\', '/')
        .replaceAll(RegExp(r'/+$'), '');
    final name = normalized.split('/').last;
    return name.isEmpty ? path : name;
  }

  bool _looksLikeRemovablePath(String path) {
    if (path.startsWith('content://')) {
      try {
        // `pathSegments` is already decoded; see `_displayNameForPath`.
        final decoded = Uri.parse(path).pathSegments.last;
        return !decoded.startsWith('primary:');
      } catch (_) {
        return false;
      }
    }
    final normalized = path.replaceAll('\\', '/').toLowerCase();
    return normalized.startsWith('/storage/') &&
        !normalized.startsWith('/storage/emulated/');
  }

  Future<bool> _isPathAvailable(String path) async {
    return await _probePathAvailability(path) ?? true;
  }

  Future<bool?> _probePathAvailability(String path) async {
    try {
      if (_availabilityProbe != null) {
        return await _availabilityProbe(path);
      }
      if (Platform.isAndroid && path.startsWith('content://')) {
        return switch (await MediaFileBridge.probeSafTreeReadAccess(path)) {
          SafTreeReadAccess.readable => true,
          SafTreeReadAccess.unreadable => false,
          SafTreeReadAccess.unknown => null,
        };
      }

      return await Directory(path).exists();
    } catch (error) {
      // A busy provider or a filesystem exception cannot prove detachment.
      _log.w('Library source access probe failed: $error');
      return null;
    }
  }

  Future<({List<String> reconnected, bool changed, int requestVersion})>
  _refreshSourceAvailabilityInDatabase() =>
      _availabilityCheckFuture ??= _checkSourceAvailability().whenComplete(() {
        _availabilityCheckFuture = null;
      });
  Future<({List<String> reconnected, bool changed, int requestVersion})>
  _checkSourceAvailability() async {
    final reconnected = <String>{};
    var changed = false;
    while (_ref.mounted) {
      final sourceVersion = _sourceVersion;
      final requestVersion = _availabilityRequestVersion;
      final sources = await _db.getSources();
      var inconclusive = false;
      for (final source in sources) {
        final available = await _probePathAvailability(source.path);
        if (!_ref.mounted ||
            sourceVersion != _sourceVersion ||
            requestVersion != _availabilityRequestVersion) {
          break;
        }
        if (available == null) {
          inconclusive = true;
          _log.w(
            'Library source access inconclusive; retaining status: ${source.id}',
          );
          continue;
        }
        if (available != source.available) {
          await _db.updateSourceState(
            source.id,
            available: available,
            lastSeenAt: available ? DateTime.now() : null,
          );
          changed = true;
          if (available && source.enabled && source.isIndexed) {
            reconnected.add(source.id);
          }
        }
      }
      if (!_ref.mounted) break;
      // A folder edit or a newer storage event supersedes pending probe
      // results. Re-read the source snapshot before applying them.
      if (sourceVersion != _sourceVersion ||
          requestVersion != _availabilityRequestVersion) {
        continue;
      }
      _availabilityRetry?.cancel();
      if (inconclusive && _availabilityRetryCount < 3) {
        _availabilityRetryCount++;
        _availabilityRetry = Timer(const Duration(seconds: 2), () {
          unawaited(refreshSourceAvailability(scanReconnected: true));
        });
      } else if (!inconclusive) {
        _availabilityRetryCount = 0;
      }
      return (
        reconnected: reconnected.toList(growable: false),
        changed: changed,
        requestVersion: requestVersion,
      );
    }
    return (
      reconnected: reconnected.toList(growable: false),
      changed: changed,
      requestVersion: _availabilityRequestVersion,
    );
  }

  Future<void> _recoverInterruptedScan() =>
      _scanRecovery ??= _recoverPreviousScan();
}
