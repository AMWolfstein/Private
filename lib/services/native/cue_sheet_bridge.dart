import 'package:sistrum/services/native/native_channel.dart';
import 'package:sistrum/utils/logging/logger.dart';

final _log = AppLogger('PlatformBridge');

/// Native CUE sheet parsing.
class CueSheetBridge {
  static Future<Map<String, dynamic>> parseCueSheet(
    String cuePath, {
    String audioDir = '',
  }) {
    _log.i('parseCueSheet: $cuePath (audioDir: $audioDir)');
    return nativeInvokeMap('parseCueSheet', {
      'cue_path': cuePath,
      'audio_dir': audioDir,
    });
  }
}
