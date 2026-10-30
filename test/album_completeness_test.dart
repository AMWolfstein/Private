import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/services/library/browse/album_completeness.dart';

void main() {
  test(
    'album assessment counts unique positions and rejects uncertain tags',
    () async {
      final result = await Process.run('python3', [
        '-c',
        r'''
import json, sqlite3, sys
query = json.loads(sys.argv[1])
db = sqlite3.connect(':memory:')
db.row_factory = sqlite3.Row
db.execute('CREATE TABLE tracks (album_key TEXT, title TEXT, track_number INTEGER, '
           'total_tracks INTEGER, disc_number INTEGER, total_discs INTEGER, unavailable INTEGER)')
def add(album, positions, total, disc=1, discs=1, unavailable=0):
    for track in positions:
        db.execute('INSERT INTO tracks VALUES (?,?,?,?,?,?,?)',
                   (album, 'Song '+str(track), track, total, disc, discs, unavailable))
add('complete', [1,2,3], 3)
add('gap', [1,3], 3)
add('one-track-album', [1], 12)
add('duplicate-incomplete', [1,1,2], 3)
add('duplicate-complete', [1,1,2], 2)
add('conflicting-total', [1], 3)
add('conflicting-total', [2], 4)
add('missing-total', [1,2], None)
add('missing-number', [0,1], 3)
add('out-of-range', [1,4], 3)
add('offline', [1,2], 3, unavailable=1)
add('disc-gap', [1,2], 2, disc=1, discs=2)
add('multi-incomplete', [1,2], 2, disc=1, discs=2)
add('multi-incomplete', [1], 3, disc=2, discs=2)
add('multi-complete', [1,2], 2, disc=1, discs=2)
add('multi-complete', [1,2,3], 3, disc=2, discs=2)
add('ambiguous', [1], 2, disc=1, discs=2)
add('ambiguous', [1], 2, disc=2, discs=2)
add('ambiguous-but-missing', [1], 10, disc=1, discs=2)
add('ambiguous-but-missing', [1], 10, disc=2, discs=2)
add('conflicting-discs', [1], 3, disc=1, discs=1)
add('conflicting-discs', [2], 3, disc=1, discs=2)
add('invalid-total', [1], 3)
add('invalid-total', [2], -1)
add('invalid-disc-total', [1], 3)
add('invalid-disc-total', [2], 3, discs=-1)
add('missing-disc-number', [1], 3, disc=0, discs=2)
add('conflicting-position', [1], 3)
db.execute("INSERT INTO tracks VALUES ('conflicting-position','Other title',1,3,1,1,0)")
rows = {row['album_key']: dict(row) for row in db.execute(query)}
def check(album, status, present, expected):
    row = rows[album]
    assert row['album_completeness'] == status, (album, row)
    assert row['album_present_tracks'] == present, (album, row)
    assert row['album_expected_tracks'] == expected, (album, row)
check('complete', 'complete', 3, 3)
check('gap', 'incomplete', 2, 3)
check('one-track-album', 'incomplete', 1, 12)
check('duplicate-incomplete', 'incomplete', 2, 3)
check('duplicate-complete', 'complete', 2, 2)
check('multi-incomplete', 'incomplete', 3, 5)
check('multi-complete', 'complete', 5, 5)
check('disc-gap', 'incomplete', 2, None)
check('ambiguous-but-missing', 'incomplete', 2, None)
for album in ['conflicting-total','missing-total','missing-number','out-of-range',
              'offline','ambiguous','conflicting-discs','missing-disc-number','conflicting-position',
              'invalid-total','invalid-disc-total']:
    assert rows[album]['album_completeness'] == 'unknown', (album, rows[album])
    assert rows[album]['album_expected_tracks'] is None, (album, rows[album])
# Filter membership must follow changes to tags and the inventory.
db.execute("INSERT INTO tracks VALUES ('gap','Song 2',2,3,1,1,0)")
missing = [row[0] for row in db.execute('SELECT album_key FROM ('+query+") WHERE album_completeness = 'incomplete'")]
assert 'gap' not in missing and 'one-track-album' in missing, missing
print('assessment passed')
''',
        jsonEncode(albumCompletenessSql('SELECT * FROM main.tracks')),
      ]);
      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect(result.stdout, contains('assessment passed'));
    },
  );

  test(
    'badge distinguishes a known count, missing disc and unknown metadata',
    () {
      expect(
        const AlbumCompleteness(
          status: 'incomplete',
          present: 8,
          expected: 12,
        ).badge,
        '8/12',
      );
      expect(
        const AlbumCompleteness(status: 'incomplete', present: 8).badge,
        '8/?',
      );
      expect(const AlbumCompleteness(status: 'unknown', present: 8).badge, '?');
      expect(AlbumCompleteness.fromRow({}), isNull);
    },
  );
}
