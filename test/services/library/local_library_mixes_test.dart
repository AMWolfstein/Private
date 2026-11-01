import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/core/models/local_library_item.dart';
import 'package:sistrum/services/library/local_library_mixes.dart';

LocalLibraryItem track(int i, {String? path}) => LocalLibraryItem(
  id: '$i',
  trackName: 'Track $i',
  artistName: 'Artist ${i % 12}',
  albumName: 'Album ${i ~/ 10}',
  filePath: path ?? '/music/$i.flac',
  scannedAt: DateTime(2026, 1, 1).add(Duration(days: i)),
  genre: i.isEven ? 'Rock' : 'Jazz',
  releaseDate: '${1990 + i % 30}',
);

void main() {
  test('daily mixes are deterministic, bounded, local and diverse', () {
    final library = List.generate(240, track);
    final first = buildLocalLibraryMixes(library, day: DateTime(2026, 11, 1));
    final second = buildLocalLibraryMixes(library, day: DateTime(2026, 11, 1));
    expect(
      first.map((m) => m.tracks.map((t) => t.id).join(',')),
      second.map((m) => m.tracks.map((t) => t.id).join(',')),
    );
    expect(first.length, inInclusiveRange(3, 10));
    for (final mix in first) {
      expect(mix.tracks.length, inInclusiveRange(6, 40));
      expect(
        mix.tracks.map((t) => t.filePath).toSet().length,
        mix.tracks.length,
      );
    }
    final daily = first.first;
    for (final artist in daily.tracks.map((t) => t.artistName).toSet()) {
      expect(
        daily.tracks.where((t) => t.artistName == artist).length,
        lessThanOrEqualTo(4),
      );
    }
    final tomorrow = buildLocalLibraryMixes(
      library,
      day: DateTime(2026, 11, 2),
    );
    expect(
      daily.tracks.map((t) => t.id),
      isNot(tomorrow.first.tracks.map((t) => t.id)),
    );
  });

  test(
    'deleted, duplicate and remote entries cannot become playable mix rows',
    () {
      final library = [
        ...List.generate(20, track),
        track(99, path: 'https://example.com/a'),
        track(88, path: ''),
        track(2),
      ];
      final result = buildLocalLibraryMixes(
        library,
        day: DateTime(2026),
        lovedIds: {'1', '3', '5', '7', '9', '11'},
      );
      for (final mix in result) {
        expect(mix.tracks.any((t) => t.id == '99' || t.id == '88'), false);
        expect(
          mix.tracks.map((t) => t.filePath).toSet().length,
          mix.tracks.length,
        );
      }
      expect(buildLocalLibraryMixes([], day: DateTime(2026)), isEmpty);
      expect(
        buildLocalLibraryMixes(library, day: DateTime(2026), target: 0),
        isEmpty,
      );
    },
  );
}
