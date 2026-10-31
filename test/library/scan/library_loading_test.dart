import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistrum/core/models/settings.dart';
import 'package:sistrum/providers/local_library_provider.dart';
import 'package:sistrum/providers/library_collections_provider.dart';
import 'package:sistrum/providers/settings_provider.dart';
import 'package:sistrum/services/library/database/library_database.dart';

part 'library_loading_1.dart';
part 'library_loading_2.dart';

class _Settings extends SettingsNotifier {
  @override
  AppSettings build() => const AppSettings();
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
  _registerLibraryLoading1();
  _registerLibraryLoading2();
}
