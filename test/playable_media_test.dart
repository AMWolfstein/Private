import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/models/playable_media.dart';

void main() {
  const full = PlayableMedia(
    id: 'track-1',
    source: 'content://media/track/1',
    title: 'Song',
    artist: 'Artist',
    album: 'Album',
    artUri: 'file:///covers/1.jpg',
    duration: Duration(milliseconds: 215000),
    bitDepth: 24,
    sampleRate: 96000,
    bitrate: 1411000,
    format: 'flac',
    explicit: true,
    genre: 'Jazz',
    autoplay: true,
  );

  test('isContentUri is true only for content:// sources', () {
    expect(full.isContentUri, isTrue);
    const local = PlayableMedia(
      id: 'a',
      source: '/music/a.mp3',
      title: '',
      artist: '',
    );
    expect(local.isContentUri, isFalse);
  });

  test('toJson and fromJson round-trip every field', () {
    final restored = PlayableMedia.fromJson(full.toJson());
    expect(restored, isNotNull);
    expect(restored!.id, full.id);
    expect(restored.source, full.source);
    expect(restored.title, full.title);
    expect(restored.artist, full.artist);
    expect(restored.album, full.album);
    expect(restored.artUri, full.artUri);
    expect(restored.duration, full.duration);
    expect(restored.bitDepth, full.bitDepth);
    expect(restored.sampleRate, full.sampleRate);
    expect(restored.bitrate, full.bitrate);
    expect(restored.format, full.format);
    expect(restored.explicit, isTrue);
    expect(restored.genre, full.genre);
    expect(restored.autoplay, isTrue);
  });

  test('toJson omits unset, zero and blank optional fields', () {
    const sparse = PlayableMedia(
      id: 'a',
      source: '/a.mp3',
      title: 'A',
      artist: 'B',
      artUri: '',
      bitrate: 0,
      format: '   ',
    );
    final json = sparse.toJson();
    expect(json.containsKey('artUri'), isFalse);
    expect(json.containsKey('durationMs'), isFalse);
    expect(json.containsKey('bitrate'), isFalse);
    expect(json.containsKey('format'), isFalse);
    expect(json.containsKey('explicit'), isFalse);
    expect(json.containsKey('autoplay'), isFalse);
  });

  test('fromJson rejects entries without an id or source', () {
    expect(PlayableMedia.fromJson({'source': '/a.mp3'}), isNull);
    expect(PlayableMedia.fromJson({'id': '', 'source': '/a.mp3'}), isNull);
    expect(PlayableMedia.fromJson({'id': 'a'}), isNull);
    expect(PlayableMedia.fromJson({'id': 'a', 'source': ''}), isNull);
  });

  test('fromJson drops non-positive quality and duration values', () {
    final restored = PlayableMedia.fromJson({
      'id': 'a',
      'source': '/a.mp3',
      'durationMs': 0,
      'bitDepth': 0,
      'sampleRate': -44100,
      'bitrate': 'x',
      'explicit': 'true',
    })!;
    expect(restored.duration, isNull);
    expect(restored.bitDepth, isNull);
    expect(restored.sampleRate, isNull);
    expect(restored.bitrate, isNull);
    expect(restored.explicit, isTrue);
    expect(restored.title, '');
    expect(restored.album, '');
  });

  test('toMediaItem uses the localized fallbacks for blank text', () {
    const blank = PlayableMedia(
      id: 'a',
      source: '/a.mp3',
      title: '',
      artist: '',
    );
    final item = blank.toMediaItem(
      unknownTitle: 'Titre inconnu',
      unknownArtist: 'Artiste inconnu',
    );
    expect(item.title, 'Titre inconnu');
    expect(item.artist, 'Artiste inconnu');
    expect(item.album, isNull);
  });

  test('toMediaItem prefers the resolved artwork over the stored one', () {
    final item = full.toMediaItem(resolvedArtwork: 'file:///resolved.jpg');
    expect(item.artUri.toString(), 'file:///resolved.jpg');
    expect(full.toMediaItem().artUri.toString(), 'file:///covers/1.jpg');
  });

  test('toMediaItem carries source, quality and trimmed format extras', () {
    final item = full.toMediaItem(resolvedSource: 'usb');
    expect(item.extras, {
      'source': 'content://media/track/1',
      'resolvedSource': 'usb',
      'bit_depth': 24,
      'sample_rate': 96000,
      'bitrate': 1411000,
      'format': 'flac',
      'explicit': true,
      'autoplay': true,
    });
    expect(item.duration, const Duration(milliseconds: 215000));
  });
}
