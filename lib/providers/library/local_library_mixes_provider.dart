import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sistrum/core/models/local_library_item.dart';
import 'package:sistrum/providers/library/library_collections_provider.dart';
import 'package:sistrum/providers/library/library_database_provider.dart';
import 'package:sistrum/providers/library/local_library_provider.dart';
import 'package:sistrum/services/library/database/library_database.dart';
import 'package:sistrum/services/library/local_library_mixes.dart';

/// Bounded, evenly spaced database pages include older library regions rather
/// than letting the most recent additions monopolize every mix.
final localLibraryMixesProvider =
    FutureProvider.autoDispose<List<LocalLibraryMix>>((ref) async {
      ref.watch(localLibraryProvider.select((s) => s.loadedIndexVersion));
      final loved = ref.watch(
        libraryCollectionsProvider.select((s) => s.loved),
      );
      final now = DateTime.now();
      final tomorrow = DateTime(now.year, now.month, now.day + 1);
      final timer = Timer(tomorrow.difference(now), ref.invalidateSelf);
      ref.onDispose(timer.cancel);
      final database = ref.watch(libraryDatabaseProvider);
      final count = (await database.getQueueCounts(
        const LibraryBrowseDbQuery(),
      )).allTrackCount;
      final tracks = <LocalLibraryItem>[];
      const pageSize = 500;
      final offsets = {
        0,
        if (count > pageSize) (count - pageSize) ~/ 2,
        if (count > pageSize) count - pageSize,
      };
      for (final offset in offsets) {
        if (!ref.mounted) return const [];
        final page = await database.getBrowseTrackPage(
          LibraryBrowseDbQuery(offset: offset, limit: pageSize),
        );
        tracks.addAll(page.rows.map(LocalLibraryItem.fromEnvelope));
      }
      return compute(_buildMixes, (
        tracks,
        now,
        loved.map((e) => e.track.id).toSet(),
      ));
    });

List<LocalLibraryMix> _buildMixes(
  (List<LocalLibraryItem>, DateTime, Set<String>) input,
) => buildLocalLibraryMixes(input.$1, day: input.$2, lovedIds: input.$3);
