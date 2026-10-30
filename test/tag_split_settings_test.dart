import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/models/settings.dart';
import 'package:sistrum/models/tag_split_settings.dart';

void main() {
  const defaults = TagSplitSettings();

  group('artists and composers', () {
    test('default delimiters split every offered symbol and word', () {
      expect(defaults.splitArtists('A; B/C، عمرو دياب، تامر حسني'), [
        'A',
        'B',
        'C',
        'عمرو دياب',
        'تامر حسني',
      ]);
      expect(defaults.splitArtists('Amr Diab, R3HAB'), ['Amr Diab', 'R3HAB']);
      expect(defaults.splitArtists('Skylar Grey, Polo G, Mozzy & Eminem'), [
        'Skylar Grey',
        'Polo G',
        'Mozzy',
        'Eminem',
      ]);
      expect(defaults.splitArtists('Daft Punk feat. Pharrell Williams'), [
        'Daft Punk',
        'Pharrell Williams',
      ]);
    });

    test('a word delimiter never splits inside a name', () {
      expect(defaults.splitArtists('Daft Punk'), ['Daft Punk']);
      expect(defaults.splitArtists('Lift Up'), ['Lift Up']);
    });

    test('configured delimiters change what is extracted', () {
      const semicolonOnly = TagSplitSettings(artistDelimiters: [';']);
      expect(semicolonOnly.splitArtists('Amr Diab, R3HAB'), [
        'Amr Diab, R3HAB',
      ]);
      const featured = TagSplitSettings(artistDelimiters: ['feat.']);
      expect(featured.splitArtists('Daft Punk feat. Pharrell Williams'), [
        'Daft Punk',
        'Pharrell Williams',
      ]);
    });

    test('turning splitting off keeps the whole tag as one name', () {
      const off = TagSplitSettings(enabled: false);
      expect(off.splitArtists('A; B/C'), ['A; B/C']);
      expect(off.splitArtists('A & B; C'), ['A & B; C']);
    });

    test('an escaped delimiter survives', () {
      expect(defaults.splitArtists(r'AC\/DC; Brian Johnson'), [
        'AC/DC',
        'Brian Johnson',
      ]);
    });

    test('unbalanced brackets from a feature are trimmed', () {
      expect(defaults.splitArtists('Artist A (ft. Artist B)'), [
        'Artist A',
        'Artist B',
      ]);
      expect(defaults.splitArtists('Band (UK)'), ['Band (UK)']);
    });

    test('a blank tag yields no names', () {
      expect(defaults.splitArtists(''), isEmpty);
      expect(defaults.splitArtists(null), isEmpty);
    });
  });

  group('genres', () {
    test('defaults are semicolon and the Arabic comma only', () {
      expect(defaults.genreDelimiters, [';', '،']);
    });

    test('combined genre entries resolve to real genres', () {
      expect(defaults.splitGenres('Soundtrack; Hip-Hop/Rap'), [
        'Soundtrack',
        'Hip-Hop/Rap',
      ]);
      expect(
        defaults.splitGenres('Hip-Hop/Rap; Hardcore Rap; Rap; Underground Rap'),
        ['Hip-Hop/Rap', 'Hardcore Rap', 'Rap', 'Underground Rap'],
      );
      expect(defaults.splitGenres('Mix'), ['Mix']);
    });

    test('slash and ampersand inside genre names are kept', () {
      expect(defaults.splitGenres('R&B/Soul'), ['R&B/Soul']);
      expect(defaults.splitGenres('Pop، Rock'), ['Pop', 'Rock']);
    });

    test('newlines separate genres even with splitting off', () {
      const off = TagSplitSettings(enabled: false);
      expect(off.splitGenres('Rock\nPop'), ['Rock', 'Pop']);
      expect(off.splitGenres('Hip-Hop/Rap; Soul'), ['Hip-Hop/Rap; Soul']);
    });

    test('genre delimiters are configured separately from artists', () {
      const slashToo = TagSplitSettings(genreDelimiters: [';', '/']);
      expect(slashToo.splitGenres('Soundtrack; Hip-Hop/Rap'), [
        'Soundtrack',
        'Hip-Hop',
        'Rap',
      ]);
      expect(slashToo.splitGenres(r'Hip-Hop\/Rap'), ['Hip-Hop/Rap']);
    });
  });

  group('settings', () {
    test('defaults are on and round trip through app settings', () {
      final fresh = AppSettings.fromJson({});
      expect(fresh.tagSplit.isDefault, isTrue);

      const changed = TagSplitSettings(
        enabled: false,
        artistDelimiters: [';', 'feat.'],
        genreDelimiters: ['/'],
      );
      final restored = AppSettings.fromJson(
        const AppSettings(tagSplit: changed).toJson(),
      ).tagSplit;
      expect(restored.enabled, isFalse);
      expect(restored.artistDelimiters, [';', 'feat.']);
      expect(restored.genreDelimiters, ['/']);
    });

    test('an emptied delimiter list falls back to the defaults', () {
      final restored = TagSplitSettings.fromJson({
        'artist_delimiters': <String>[],
        'genre_delimiters': ['  ', ''],
      });
      expect(restored.artistDelimiters, kArtistDelimiters);
      expect(restored.genreDelimiters, kGenreDelimiters);
    });
  });
}
