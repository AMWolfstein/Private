import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistrum/models/settings.dart';
import 'package:sistrum/providers/local_library_provider.dart';
import 'package:sistrum/providers/library_collections_provider.dart';
import 'package:sistrum/providers/settings_provider.dart';
import 'package:sistrum/services/library_database.dart';

class _Settings extends SettingsNotifier {
  _Settings({Future<void>? ready, String path = ''})
    : _ready = ready,
      _path = path;

  final Future<void>? _ready;
  final String _path;

  @override
  AppSettings build() => const AppSettings();

  @override
  Future<void> ensureLoaded() async {
    await _ready;
    state = state.copyWith(localLibraryPath: _path);
  }
}

class _LibraryDatabase implements LibraryDatabase {
  _LibraryDatabase(this.sources);

  List<LocalLibrarySource> sources;
  Future<int> Function() count = () async => 2;
  bool failSources = false;
  int sourceReads = 0;
  int countReads = 0;
  int availabilityWrites = 0;
  final removedIds = <String>[];

  @override
  Future<List<String>> getPhysicalFileIds(Iterable<String> filePaths) async =>
      filePaths.contains('/music/deleted.flac') ? ['deleted', 'alias'] : [];

  @override
  Future<void> deleteByIds(Iterable<String> ids) async =>
      removedIds.addAll(ids);

  @override
  Future<List<LocalLibrarySource>> getSources() async {
    sourceReads++;
    if (failSources) throw StateError('database is busy');
    return List.of(sources);
  }

  @override
  Future<int> getCount() {
    countReads++;
    return count();
  }

  @override
  Future<void> removeSource(String sourceId) async {
    sources = sources.where((source) => source.id != sourceId).toList();
  }

  @override
  Future<LocalLibrarySource?> getSourceByPath(String path) async =>
      sources.where((source) => source.path == path).firstOrNull;

  @override
  Future<void> migrateLegacySource({
    required String path,
    required String displayName,
    String? bookmark,
    String? volumeId,
    bool isRemovable = false,
    bool available = true,
    DateTime? lastScannedAt,
  }) async {
    sources = [
      ...sources,
      LocalLibrarySource(
        id: LibraryDatabase.legacySourceId,
        path: path,
        displayName: displayName,
        available: available,
      ),
    ];
  }

  @override
  Future<void> updateSourceState(
    String sourceId, {
    bool? enabled,
    bool? available,
    DateTime? lastScannedAt,
    DateTime? lastSeenAt,
    String? lastScanError,
    bool clearLastScanError = false,
  }) async {
    if (available != null) availabilityWrites++;
    sources = [
      for (final source in sources)
        source.id == sourceId
            ? source.copyWith(enabled: enabled, available: available)
            : source,
    ];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Library extends LocalLibraryNotifier {
  _Library(LibraryDatabase database, LocalLibraryAvailabilityProbe probe)
    : super(database: database, availabilityProbe: probe);

  final List<String> scannedSources = [];

  @override
  Future<void> startSourceScan(
    String sourceId, {
    bool forceFullScan = false,
  }) async {
    scannedSources.add(sourceId);
  }
}

class _Collections extends LibraryCollectionsNotifier {
  final removedIds = <String>[];
  bool failRemoval = false;

  @override
  LibraryCollectionsState build() => LibraryCollectionsState(isLoaded: true);

  @override
  Future<void> removeLocalLibraryTracks(Iterable<String> ids) async {
    if (failRemoval) throw StateError('collection deletion failed');
    removedIds.addAll(ids);
  }
}

Future<void> _waitFor(bool Function() condition) async {
  for (var i = 0; i < 50 && !condition(); i++) {
    await Future<void>.delayed(Duration.zero);
  }
  expect(condition(), isTrue);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory music;
  late _LibraryDatabase database;
  late ProviderContainer container;
  late LocalLibraryAvailabilityProbe probe;
  late _Library library;
  late _Collections collections;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    music = await Directory.systemTemp.createTemp('library_loading_');
    database = _LibraryDatabase([
      LocalLibrarySource(
        id: 'music',
        path: music.path,
        displayName: 'Music',
        trackCount: 2,
      ),
    ]);
    probe = (path, {bookmark}) => Directory(path).exists();
    collections = _Collections();
    container = ProviderContainer(
      overrides: [
        libraryCollectionsProvider.overrideWith(() => collections),
        settingsProvider.overrideWith(_Settings.new),
        localLibraryProvider.overrideWith(
          () => library = _Library(
            database,
            (path, {bookmark}) => probe(path, bookmark: bookmark),
          ),
        ),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await music.delete(recursive: true);
  });

  test(
    'upgrade waits for saved settings before migrating the old folder',
    () async {
      final ready = Completer<void>();
      container.dispose();
      database.sources = [];
      container = ProviderContainer(
        overrides: [
          settingsProvider.overrideWith(
            () => _Settings(ready: ready.future, path: music.path),
          ),
          localLibraryProvider.overrideWith(
            () => LocalLibraryNotifier(database: database),
          ),
        ],
      );
      container.read(localLibraryProvider);
      await Future<void>.delayed(Duration.zero);
      expect(container.read(localLibraryProvider).isLoading, isTrue);
      ready.complete();
      await _waitFor(() => !container.read(localLibraryProvider).isLoading);
      expect(container.read(localLibraryProvider).loadFailed, isFalse);
      expect(
        container.read(localLibraryProvider).sources.single.path,
        music.path,
      );
      expect(
        container.read(localLibraryProvider).sources.single.id,
        LibraryDatabase.legacySourceId,
      );
    },
  );

  test(
    'saved folders appear while a large track count is still loading',
    () async {
      final pending = Completer<int>();
      database.count = () => pending.future;
      container.read(localLibraryProvider);
      await _waitFor(
        () => container.read(localLibraryProvider).sources.isNotEmpty,
      );
      final loading = container.read(localLibraryProvider);
      expect(loading.sources.single.path, music.path);
      expect(loading.isLoading, isTrue);
      pending.complete(2);
      await _waitFor(() => !container.read(localLibraryProvider).isLoading);
      expect(container.read(localLibraryProvider).totalCount, 2);
    },
  );

  test(
    'summary failure retains folders and retry recovers without reattaching',
    () async {
      database.count = () async => throw StateError('count read failed');
      container.read(localLibraryProvider);
      await _waitFor(() => !container.read(localLibraryProvider).isLoading);
      final failed = container.read(localLibraryProvider);
      expect(failed.loadFailed, isTrue);
      expect(failed.sources.single.path, music.path);
      database.count = () async => 2;
      await container.read(localLibraryProvider.notifier).reloadFromStorage();
      expect(container.read(localLibraryProvider).loadFailed, isFalse);
      expect(container.read(localLibraryProvider).totalCount, 2);
      expect(container.read(localLibraryProvider).sources.single.id, 'music');
    },
  );

  for (final edit in ['disable', 'enable', 'remove']) {
    test('initial index cannot overwrite a newer source $edit', () async {
      if (edit == 'enable') {
        database.sources = [database.sources.single.copyWith(enabled: false)];
      }
      int currentCount() => database.sources
          .where((source) => source.enabled && source.available)
          .fold<int>(0, (total, source) => total + source.trackCount);
      final pending = Completer<int>();
      database.count = () => pending.future;
      container.read(localLibraryProvider);
      await _waitFor(() => database.countReads > 0);
      // The in-flight read holds the pre-edit count; a retry must read the
      // post-edit state instead of what this stale read returns.
      final staleCount = currentCount();
      database.count = () async => currentCount();
      if (edit == 'remove') {
        await library.removeSource('music');
      } else {
        await library.setSourceEnabled('music', edit == 'enable');
      }
      final version = container.read(localLibraryProvider).loadedIndexVersion;
      pending.complete(staleCount);
      await _waitFor(() => !container.read(localLibraryProvider).isLoading);
      final loaded = container.read(localLibraryProvider);
      expect(loaded.loadFailed, false);
      expect(loaded.loadedIndexVersion, version);
      expect(loaded.totalCount, edit == 'enable' ? 2 : 0);
      if (edit == 'remove') {
        expect(loaded.sources, isEmpty);
      } else {
        expect(loaded.sources.single.enabled, edit == 'enable');
      }
    });
  }

  const backendChannel = MethodChannel('com.amwolfstein.sistrum/backend');

  /// Records native calls made while [body] runs; other channel traffic is
  /// irrelevant here and answered with null.
  Future<List<MethodCall>> recordBackendCalls(
    Future<void> Function() body,
  ) async {
    final calls = <MethodCall>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(backendChannel, (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(backendChannel, null));
    await body();
    return calls;
  }

  test('removing the last source on a tree releases its grant', () async {
    const tree =
        'content://com.android.externalstorage.documents/tree/primary%3AMusic';
    database.sources = [
      LocalLibrarySource(
        id: 'saf',
        path: tree,
        displayName: 'Music',
        trackCount: 2,
      ),
    ];
    container.read(localLibraryProvider);
    await _waitFor(() => !container.read(localLibraryProvider).isLoading);
    final calls = await recordBackendCalls(() => library.removeSource('saf'));
    final releases = calls.where((call) => call.method == 'safReleaseTree');
    expect(releases.map((call) => call.arguments), [
      {'tree_uri': tree},
    ]);
    expect(container.read(localLibraryProvider).sources, isEmpty);
  });

  test('a shared tree keeps its grant until its last source is gone', () async {
    const tree =
        'content://com.android.externalstorage.documents/tree/primary%3AMusic';
    database.sources = [
      LocalLibrarySource(
        id: 'saf-a',
        path: tree,
        displayName: 'Music',
        trackCount: 1,
      ),
      LocalLibrarySource(
        id: 'saf-b',
        path: tree,
        displayName: 'Music',
        trackCount: 1,
      ),
    ];
    container.read(localLibraryProvider);
    await _waitFor(() => !container.read(localLibraryProvider).isLoading);
    final first = await recordBackendCalls(() => library.removeSource('saf-a'));
    expect(first.where((call) => call.method == 'safReleaseTree'), isEmpty);
    final second = await recordBackendCalls(
      () => library.removeSource('saf-b'),
    );
    expect(
      second
          .where((call) => call.method == 'safReleaseTree')
          .map((call) => call.arguments),
      [
        {'tree_uri': tree},
      ],
    );
  });

  test(
    'failed reload keeps the previously loaded folders and song count',
    () async {
      container.read(localLibraryProvider);
      await _waitFor(() => !container.read(localLibraryProvider).isLoading);
      database.failSources = true;
      await container.read(localLibraryProvider.notifier).reloadFromStorage();
      final failed = container.read(localLibraryProvider);
      expect(failed.loadFailed, isTrue);
      expect(failed.totalCount, 2);
      expect(failed.sources.single.id, 'music');
      database.failSources = false;
      await container.read(localLibraryProvider.notifier).reloadFromStorage();
      expect(container.read(localLibraryProvider).loadFailed, isFalse);
    },
  );

  test(
    'unchanged overlapping availability refreshes share one probe',
    () async {
      container.read(localLibraryProvider);
      await _waitFor(() => !container.read(localLibraryProvider).isLoading);
      final sourceReads = database.sourceReads;
      final countReads = database.countReads;
      final version = container.read(localLibraryProvider).loadedIndexVersion;
      final refresh = library.refreshSourceAvailability();
      final overlapping = library.refreshSourceAvailability();
      expect(identical(refresh, overlapping), isTrue);
      await Future.wait([refresh, overlapping]);
      expect(database.sourceReads, sourceReads + 1);
      expect(database.countReads, countReads);
      expect(container.read(localLibraryProvider).loadedIndexVersion, version);
    },
  );

  test('detach and reconnect each refresh the visible index once', () async {
    database.count = () async => database.sources.single.available ? 2 : 0;
    container.read(localLibraryProvider);
    await _waitFor(() => !container.read(localLibraryProvider).isLoading);
    final version = container.read(localLibraryProvider).loadedIndexVersion;
    final countReads = database.countReads;
    probe = (path, {bookmark}) async => false;
    await library.refreshSourceAvailability();
    expect(
      container.read(localLibraryProvider).sources.single.available,
      false,
    );
    expect(container.read(localLibraryProvider).totalCount, 0);
    expect(
      container.read(localLibraryProvider).loadedIndexVersion,
      version + 1,
    );

    probe = (path, {bookmark}) async => true;
    await Future.wait([
      library.refreshSourceAvailability(),
      library.refreshSourceAvailability(scanReconnected: true),
    ]);
    expect(container.read(localLibraryProvider).sources.single.available, true);
    expect(container.read(localLibraryProvider).totalCount, 2);
    expect(
      container.read(localLibraryProvider).loadedIndexVersion,
      version + 2,
    );
    expect(database.countReads, countReads + 2);
    await _waitFor(() => library.scannedSources.isNotEmpty);
    expect(library.scannedSources, ['music']);
  });

  test(
    'an inconclusive probe retains availability and the loaded index',
    () async {
      container.read(localLibraryProvider);
      await _waitFor(() => !container.read(localLibraryProvider).isLoading);
      final countReads = database.countReads;
      final version = container.read(localLibraryProvider).loadedIndexVersion;
      probe = (path, {bookmark}) async => null;
      await library.refreshSourceAvailability();
      expect(
        container.read(localLibraryProvider).sources.single.available,
        true,
      );
      expect(database.countReads, countReads);
      expect(container.read(localLibraryProvider).loadedIndexVersion, version);
    },
  );

  test('a newer storage event supersedes a pending detached result', () async {
    container.read(localLibraryProvider);
    await _waitFor(() => !container.read(localLibraryProvider).isLoading);
    final pending = Completer<bool?>();
    var probes = 0;
    probe = (path, {bookmark}) =>
        ++probes == 1 ? pending.future : Future<bool?>.value(true);
    final countReads = database.countReads;
    final refresh = library.refreshSourceAvailability();
    await _waitFor(() => probes == 1);
    final reconnect = library.refreshSourceAvailability(scanReconnected: true);
    pending.complete(false);
    await Future.wait([refresh, reconnect]);
    expect(probes, 2);
    expect(database.availabilityWrites, 0);
    expect(database.countReads, countReads);
    expect(container.read(localLibraryProvider).sources.single.available, true);
  });

  for (final remove in [false, true]) {
    test(
      'pending probes do not overwrite ${remove ? 'removal' : 'disable'}',
      () async {
        container.read(localLibraryProvider);
        await _waitFor(() => !container.read(localLibraryProvider).isLoading);
        final pending = Completer<bool?>();
        var probes = 0;
        probe = (path, {bookmark}) =>
            ++probes == 1 ? pending.future : Future<bool?>.value(true);
        final refresh = library.refreshSourceAvailability();
        await _waitFor(() => probes == 1);
        if (remove) {
          await library.removeSource('music');
        } else {
          await library.setSourceEnabled('music', false);
        }
        final countReads = database.countReads;
        final version = container.read(localLibraryProvider).loadedIndexVersion;
        pending.complete(false);
        await refresh;
        expect(database.availabilityWrites, 0);
        expect(database.countReads, countReads);
        expect(
          container.read(localLibraryProvider).loadedIndexVersion,
          version,
        );
        final sources = container.read(localLibraryProvider).sources;
        if (remove) {
          expect(sources, isEmpty);
        } else {
          expect(sources.single.enabled, false);
          expect(sources.single.available, true);
        }
      },
    );
  }

  test('a superseded summary cannot restore stale counts', () async {
    container.read(localLibraryProvider);
    await _waitFor(() => !container.read(localLibraryProvider).isLoading);
    final pending = Completer<int>();
    database.count = () => pending.future;
    probe = (path, {bookmark}) async => false;
    final countReads = database.countReads;
    final refresh = library.refreshSourceAvailability();
    await _waitFor(() => database.countReads > countReads);
    // The superseded read still returns the old count; every fresh read after
    // the source is disabled must see 0.
    database.count = () async => 0;
    await library.setSourceEnabled('music', false);
    pending.complete(2);
    await refresh;
    expect(container.read(localLibraryProvider).sources.single.enabled, false);
    expect(container.read(localLibraryProvider).totalCount, 0);
  });

  test('an unavailable folder remains attached instead of vanishing', () async {
    await music.delete(recursive: true);
    database.sources = [
      LocalLibrarySource(
        id: 'missing',
        path: music.path,
        displayName: 'Offline music',
        isRemovable: true,
        available: false,
      ),
    ];
    database.count = () async => 0;
    container.read(localLibraryProvider);
    await _waitFor(() => !container.read(localLibraryProvider).isLoading);
    final loaded = container.read(localLibraryProvider);
    expect(loaded.loadFailed, isFalse);
    expect(loaded.sources.single.available, isFalse);
    expect(loaded.sources.single.path, music.path);
    // Keep teardown simple after deliberately removing the storage above.
    await music.create();
  });

  test('reload invalidates a summary already being read', () async {
    final first = Completer<int>();
    database.count = () => first.future;
    container.read(localLibraryProvider);
    await _waitFor(() => database.countReads == 1);
    database.count = () async => 7;
    final reloaded = library.reloadFromStorage();
    first.complete(2);
    await reloaded;
    final current = container.read(localLibraryProvider);
    expect(database.countReads, 2);
    expect(current.totalCount, 7);
    expect(current.isLoading, isFalse);
  });

  test(
    'concurrent reloads share the retry after an earlier read fails',
    () async {
      final old = Completer<int>();
      final retry = Completer<int>();
      database.count = () => old.future;
      container.read(localLibraryProvider);
      await _waitFor(() => database.countReads == 1);
      database.count = () => retry.future;
      final firstReload = library.reloadFromStorage();
      final secondReload = library.reloadFromStorage();
      old.completeError(StateError('stale read failed'));
      await _waitFor(() => database.countReads == 2);
      retry.complete(2);
      await Future.wait([firstReload, secondReload]);
      expect(database.countReads, 2);
      expect(container.read(localLibraryProvider).totalCount, 2);
    },
  );

  test(
    'physical deletion removes collection references for every indexed alias',
    () async {
      container.read(localLibraryProvider);
      await _waitFor(() => !container.read(localLibraryProvider).isLoading);
      await library.removePhysicalFiles(['/music/deleted.flac']);
      expect(collections.removedIds, ['deleted', 'alias']);
      expect(database.removedIds, ['deleted', 'alias']);
    },
  );

  test(
    'collection cleanup failure retains row identity for deletion retry',
    () async {
      container.read(localLibraryProvider);
      await _waitFor(() => !container.read(localLibraryProvider).isLoading);
      collections.failRemoval = true;
      await expectLater(library.removeItems(['deleted']), throwsStateError);
      expect(database.removedIds, isEmpty);
      collections.failRemoval = false;
      await library.removeItems(['deleted']);
      expect(database.removedIds, ['deleted']);
    },
  );
}
