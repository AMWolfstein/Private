import 'dart:math';
import 'package:sistrum/core/models/local_library_item.dart';
import 'package:sistrum/utils/text/lookup_text.dart';

enum LocalMixKind { daily, favorites, genre, artist, decade, fresh }

class LocalLibraryMix {
  const LocalLibraryMix(this.id, this.kind, this.label, this.tracks);
  final String id;
  final LocalMixKind kind;
  final String label;
  final List<LocalLibraryItem> tracks;
}

/// Deterministic daily selection. Never persists duplicate library entries or
/// imports remote sources. Inputs are bounded by the provider's sample budget.
List<LocalLibraryMix> buildLocalLibraryMixes(
  List<LocalLibraryItem> library, {
  required DateTime day,
  Set<String> lovedIds = const {},
  int target = 40,
}) {
  if (target <= 0) return const [];
  final unique = <String, LocalLibraryItem>{};
  for (final item in library) {
    final uri = Uri.tryParse(item.filePath);
    if (item.filePath.isEmpty ||
        uri == null ||
        (uri.hasScheme && uri.scheme != 'content' && uri.scheme != 'file')) {
      continue;
    }
    unique.putIfAbsent(item.filePath, () => item);
  }
  if (unique.length < 6) return const [];
  final random = Random(day.year * 10000 + day.month * 100 + day.day);
  final all = unique.values.toList()..shuffle(random);
  final mixes = <LocalLibraryMix>[];
  void add(
    LocalMixKind kind,
    String label,
    List<LocalLibraryItem> pool, {
    bool diversify = true,
  }) {
    if (pool.length < 6 || mixes.length >= 10) return;
    final remaining = List<LocalLibraryItem>.of(pool);
    final tracks = <LocalLibraryItem>[];
    final artists = <String, int>{};
    // Greedy fair scheduling: choose the least represented artist next.
    while (tracks.length < target && remaining.isNotEmpty) {
      var best = 0;
      if (diversify) {
        for (var i = 1; i < remaining.length; i++) {
          if ((artists[normalizeLookupText(remaining[i].artistName)] ?? 0) <
              (artists[normalizeLookupText(remaining[best].artistName)] ?? 0)) {
            best = i;
          }
        }
      }
      final next = remaining.removeAt(best);
      tracks.add(next);
      final artist = normalizeLookupText(next.artistName);
      artists[artist] = (artists[artist] ?? 0) + 1;
    }
    final sources = tracks.map((t) => t.filePath).toSet();
    if (mixes.any(
      (m) =>
          m.tracks.where((t) => sources.contains(t.filePath)).length /
              min(m.tracks.length, tracks.length) >
          0.8,
    )) {
      return;
    }
    mixes.add(
      LocalLibraryMix(
        '${kind.name}:${normalizeLookupText(label)}',
        kind,
        label,
        List.unmodifiable(tracks),
      ),
    );
  }

  add(LocalMixKind.daily, '', all);
  add(
    LocalMixKind.favorites,
    '',
    all.where((t) => lovedIds.contains(t.id)).toList(),
  );
  final fresh = List<LocalLibraryItem>.of(all)
    ..sort((a, b) => b.scannedAt.compareTo(a.scannedAt));
  add(LocalMixKind.fresh, '', fresh.take(target).toList(), diversify: false);
  for (final kind in [
    LocalMixKind.genre,
    LocalMixKind.artist,
    LocalMixKind.decade,
  ]) {
    final groups = <String, List<LocalLibraryItem>>{};
    final labels = <String, String>{};
    for (final item in all) {
      final values = switch (kind) {
        LocalMixKind.genre => (item.genre ?? '').split(RegExp(r'[,;/]')),
        LocalMixKind.artist => [item.artistName],
        _ => [
          if (int.tryParse((item.releaseDate ?? '').split('-').first)
              case final int year when year >= 1900 && year <= day.year)
            '${year ~/ 10 * 10}s',
        ],
      };
      for (final value in values) {
        final key = normalizeLookupText(value);
        if (key.isEmpty) continue;
        labels[key] = value.trim();
        final group = groups.putIfAbsent(key, () => []);
        if (!group.contains(item)) group.add(item);
      }
    }
    final keys = groups.keys.toList()
      ..sort((a, b) => groups[b]!.length.compareTo(groups[a]!.length));
    for (final key in keys.take(3)) {
      add(
        kind,
        labels[key]!,
        groups[key]!,
        diversify: kind != LocalMixKind.artist,
      );
    }
  }
  return List.unmodifiable(mixes);
}
