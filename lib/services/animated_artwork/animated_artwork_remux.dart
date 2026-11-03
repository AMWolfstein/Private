import 'dart:io';

import 'package:sistrum/services/animated_artwork/animated_artwork_download.dart';
import 'package:sistrum/services/ffmpeg/ffmpeg_support.dart';

/// Rewrites [input] into [output] as a self-contained MP4 with its index first
/// and no audio. Returns false when FFmpeg cannot do it.
typedef AnimatedVideoRemux = Future<bool> Function(String input, String output);

/// Returns true when FFmpeg decodes every frame of [path] without errors.
typedef AnimatedVideoDecodeCheck = Future<bool> Function(String path);

/// Overridable in tests. Production runs FFmpeg with the same bounds Mornye
/// uses for motion covers: copied video, 30 seconds, 24 MiB, faststart.
AnimatedVideoRemux animatedVideoRemux = _ffmpegRemux;

/// Overridable in tests. Production decodes the whole video, so a stream that
/// only looks valid to the container check is rejected before publication.
AnimatedVideoDecodeCheck animatedVideoDecodes = _ffmpegDecodes;

Future<bool> _ffmpegRemux(String input, String output) async {
  final result = await FFmpegExecution.arguments([
    '-y',
    '-i',
    input,
    '-map',
    '0:v:0',
    '-an',
    '-sn',
    '-dn',
    '-c:v',
    'copy',
    '-t',
    '30',
    '-fs',
    '$kAnimatedArtworkMaxBytes',
    '-movflags',
    '+faststart',
    output,
  ]);
  return result.success;
}

Future<bool> _ffmpegDecodes(String path) async {
  final result = await FFmpegExecution.arguments([
    '-v',
    'error',
    '-xerror',
    '-err_detect',
    'explode',
    '-i',
    path,
    '-map',
    '0:v:0',
    '-an',
    '-f',
    'null',
    '-',
  ]);
  return result.success;
}

/// Replaces [video] with a remuxed copy that FFmpeg decodes cleanly. The
/// original is replaced only after both steps pass, and a failure is a stable
/// unsupported-media answer, so the caller records it as a miss.
Future<DownloadedAnimatedVideo> preparePlayableVideo(
  DownloadedAnimatedVideo video,
) async {
  final input = video.file;
  final remuxed = File('${input.path}.remux.mp4');
  try {
    if (!await animatedVideoRemux(input.path, remuxed.path)) {
      throw const AnimatedVideoDownloadException(
        AnimatedVideoFailure.unsupportedMedia,
        'remux',
      );
    }
    if (!await animatedVideoDecodes(remuxed.path)) {
      throw const AnimatedVideoDownloadException(
        AnimatedVideoFailure.unsupportedMedia,
        'decode',
      );
    }
    await validateMp4(remuxed);
    await remuxed.rename(input.path);
    return DownloadedAnimatedVideo(
      file: input,
      bytes: await input.length(),
      width: video.width,
      height: video.height,
    );
  } on FileSystemException {
    throw const AnimatedVideoDownloadException(
      AnimatedVideoFailure.unsupportedMedia,
      'publish',
    );
  } finally {
    if (await remuxed.exists()) await remuxed.delete();
  }
}
