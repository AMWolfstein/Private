import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/services/library/metadata_edit_result.dart';

void main() {
  test('a native method completes the edit', () {
    final result = MetadataEditResult.decode({
      'success': true,
      'method': 'native_mp3',
    });
    expect(result.outcome, MetadataEditOutcome.completed);
    expect(result.isNativeMethod, isTrue);
    expect(result.error, isNull);
  });

  test('an ffmpeg method stages a temp file for the fallback writer', () {
    final result = MetadataEditResult.decode({
      'success': true,
      'method': 'ffmpeg',
      'temp_path': '/cache/temp_embed.opus',
      'saf_uri': 'content://library/song.opus',
    });
    expect(result.outcome, MetadataEditOutcome.ffmpegStaged);
    expect(result.isNativeMethod, isFalse);
    expect(result.tempPath, '/cache/temp_embed.opus');
    expect(result.safUri, 'content://library/song.opus');
  });

  test('an error response fails with its message', () {
    final result = MetadataEditResult.decode({'error': 'tag write failed'});
    expect(result.outcome, MetadataEditOutcome.failed);
    expect(result.error, 'tag write failed');
  });

  test('a failure without an error message is still a failure', () {
    final result = MetadataEditResult.decode({
      'success': false,
      'method': 'native_mp3',
    });
    expect(result.outcome, MetadataEditOutcome.failed);
    expect(result.error, 'Native metadata edit reported failure');
  });

  test('a response without a method is not treated as saved', () {
    final result = MetadataEditResult.decode({'success': true});
    expect(result.outcome, MetadataEditOutcome.failed);
    expect(result.error, 'Native metadata edit returned no method');
  });
}
