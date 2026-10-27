import 'dart:collection';
import 'package:sistrum/models/track.dart';
import 'package:sistrum/providers/library_collections_provider.dart';
import 'package:sistrum/screens/library_tracks_folder_data.dart';
import 'package:flutter_test/flutter_test.dart';

class _ReadCountingList<T> extends ListBase<T> {
  _ReadCountingList(this.values);
  final List<T> values;
  int reads = 0;
  @override
  int get length => values.length;
  @override
  set length(int value) => throw UnsupportedError('immutable');
  @override
  T operator [](int index) {
    reads++;
    return values[index];
  }

  @override
  void operator []=(int index, T value) => throw UnsupportedError('immutable');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('unchanged collection snapshot does no additional full-list reads', () {
    final entries = _ReadCountingList(
      List.generate(
        4000,
        (index) => CollectionTrackEntry(
          key: '$index',
          addedAt: DateTime.utc(2026),
          track: Track(
            id: '$index',
            name: 'Song $index',
            artistName: 'Artist',
            albumName: 'Album',
            duration: 1,
          ),
        ),
      ),
    );
    final data = LibraryTracksFolderData()..update(entries);
    final snapshot = data.tracks;
    final keys = data.keys;
    final reads = entries.reads;
    for (var i = 0; i < 100; i++) {
      data.update(entries);
      expect(identical(data.tracks, snapshot), isTrue);
      expect(identical(data.keys, keys), isTrue);
    }
    expect(entries.reads, reads);
    expect(data.keys.length, 4000);
    expect(() => data.tracks.clear(), throwsUnsupportedError);
    data.update(entries.take(2).toList());
    expect(data.keys, {'0', '1'});
    expect(data.tracks.length, 2);
  });
}
