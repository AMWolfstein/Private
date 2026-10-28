import 'package:ffmpeg_kit_flutter_new_audio/ffprobe_kit.dart';
import 'package:sistrum/utils/logger.dart';

final _log = AppLogger('FFmpeg');

/// Image inspection for local artwork.
abstract final class FFmpegProbe {
  static ({int width, int height})? imageDimensionsFromProperties(
    Map<dynamic, dynamic> properties,
  ) {
    final width = int.tryParse(properties['width']?.toString() ?? '');
    final height = int.tryParse(properties['height']?.toString() ?? '');
    if (width == null || height == null || width <= 0 || height <= 0) {
      return null;
    }
    return (width: width, height: height);
  }

  static Future<({int width, int height})?> imageDimensions(String path) async {
    try {
      final info = (await FFprobeKit.getMediaInformation(
        path,
      )).getMediaInformation();
      if (info == null) return null;
      for (final stream in info.getStreams()) {
        final dimensions = imageDimensionsFromProperties(
          stream.getAllProperties() ?? const <String, dynamic>{},
        );
        if (dimensions != null) return dimensions;
      }
    } catch (e) {
      _log.w('Cover dimension probe failed for $path: $e');
    }
    return null;
  }
}
