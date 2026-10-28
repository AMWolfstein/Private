import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'support/library_collections_benchmark.dart';

void main() {
  test('measurement separates caller ordering from heartbeat counts', () async {
    final synchronous = await measureCollectionOperation(() => 42);
    expect(synchronous.value, 42);
    expect(synchronous.yieldedBeforeCompletion, isFalse);
    final completed = await measureCollectionOperation(() => Future.value(42));
    expect(completed.yieldedBeforeCompletion, isFalse);
    final release = Completer<int>();
    final pending = measureCollectionOperation(() => release.future);
    // An event handshake, not a minimum elapsed-time or heartbeat requirement.
    Timer.run(() => release.complete(42));
    final asynchronous = await pending;
    expect(asynchronous.value, 42);
    expect(asynchronous.yieldedBeforeCompletion, isTrue);
    expect(
      asynchronous.timing.keys,
      containsAll(['microseconds', 'heartbeat_count', 'maximum_gap_us']),
    );
  });

  test(
    'paired large collection workers benchmark',
    () async {
      final report = {
        'platform': Platform.operatingSystem,
        'mode': 'flutter test host',
        'collection_hydration': await benchmarkCollectionHydration(),
        'playlist_search': await benchmarkPlaylistSearch(),
        'playlist_metadata_copy': await benchmarkPlaylistMetadataCopy(),
        'collection_export': await benchmarkCollectionExport(),
      };
      const output = String.fromEnvironment('COLLECTIONS_BENCHMARK_OUTPUT');
      if (output.isNotEmpty) {
        final file = File(output);
        await file.parent.create(recursive: true);
        await file.writeAsString(
          const JsonEncoder.withIndent('  ').convert(report),
        );
      }
      expect(report['collection_hydration'], isA<Map<String, dynamic>>());
    },
    skip: !const bool.fromEnvironment('RUN_COLLECTIONS_BENCHMARK'),
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
