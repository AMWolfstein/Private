import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/l10n/l10n.dart';
import 'package:sistrum/screens/stats/listening_rewind_screen.dart';
import 'package:sistrum/services/playback/stats/listening_rewind.dart';
import 'package:sistrum/services/playback/stats/listening_statistics.dart';
import 'package:sistrum/core/theme/app_theme.dart';

import '../../../support/sqlite_process_database.dart';

part 'listening_rewind_aggregates.dart';
part 'listening_rewind_slides.dart';

Map<String, Object?> _row(
  String day,
  String key, {
  String artist = 'Artist',
  String album = 'Album',
  int minutes = 10,
  int plays = 1,
}) => {
  'day': day,
  'track_key': key,
  'title': 'Song $key',
  'artist': artist,
  'album': album,
  'artwork': null,
  'milliseconds': minutes * 60000,
  'plays': plays,
};

final _range = ListeningRewindRange.of(
  ListeningRewindPeriod.weeks,
  DateTime(2026, 10, 14, 21),
);

ListeningRewind _sample({Set<String>? newArtists, ListeningReplay? replay}) =>
    ListeningRewind.compute(
      range: _range,
      summary: ListeningSummary.fromRows([
        _row('2026-10-01', 'a', minutes: 30, plays: 3),
        _row('2026-10-02', 'a', minutes: 20, plays: 2),
        _row('2026-10-03', 'b', album: 'ALBUM', minutes: 15),
        _row('2026-10-05', 'c', artist: 'Other', album: 'Else', minutes: 40),
        _row('2026-10-06', 'd', artist: 'Fresh', album: '', minutes: 5),
      ]),
      previousMilliseconds: 100 * 60000,
      newArtistNames: newArtists,
      replay: replay,
    );

final _yearRange = ListeningRewindRange.of(
  ListeningRewindPeriod.year,
  DateTime(2026, 10, 14, 21),
);

ListeningRewind _yearSample() => ListeningRewind.compute(
  range: _yearRange,
  summary: ListeningSummary.fromRows([
    _row('2026-01-02', 'a', minutes: 30, plays: 3),
    _row('2026-01-03', 'b', artist: 'Other', minutes: 20),
    _row('2026-03-10', 'c', artist: 'Third', album: 'Else', minutes: 90),
    _row('2026-10-01', 'a', minutes: 40, plays: 4),
  ]),
  previousMilliseconds: 0,
  year: ListeningYearDetails(
    monthlyTopArtists: const {1: 'Artist', 3: 'Third', 10: 'Artist'},
    loyalArtist: 'Artist',
    loyalArtistDays: 2,
    firstPlay: ListeningFirstPlay(
      const ListeningTrack(
        key: 'a',
        title: 'Song a',
        artist: 'Artist',
        album: 'Album',
      ),
      DateTime(2026, 1, 2),
    ),
  ),
);

void main() {
  _registerListeningRewindAggregates();
  _registerListeningRewindSlides();
}
