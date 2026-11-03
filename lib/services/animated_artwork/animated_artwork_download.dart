// Adapted for Sistrum from Mornye and Mornye-Extension (LGPL-3.0-only,
// Copyright 2026 zarzet and contributors); see assets/licenses/animated_artwork.txt.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// Largest animated artwork file accepted, in bytes.
const kAnimatedArtworkMaxBytes = 24 * 1024 * 1024;

/// Largest side of a video frame, in pixels. Apple motion artwork is well
/// below this; larger declared sizes are treated as unsupported.
const kAnimatedArtworkMaxSide = 3840;

/// Why an animated video could not be published. Every failure leaves the
/// previous video in place; this only describes the attempt.
enum AnimatedVideoFailure {
  /// The playlist is not a single-file MP4 that can be fetched whole.
  unsupportedMedia,

  /// Too many bytes, too large a frame, or the request outlived its deadline.
  tooLarge,

  /// The download ended early or did not match its own declared length.
  incomplete,

  /// The bytes are not an MP4 with a movie header.
  invalidContainer,

  /// The network or the host failed while downloading.
  network,

  /// The caller cancelled the request (manual choice, Reset, Clear, off).
  cancelled,
}

class AnimatedVideoDownloadException implements Exception {
  const AnimatedVideoDownloadException(this.failure, [this.detail]);
  final AnimatedVideoFailure failure;
  final String? detail;

  @override
  String toString() =>
      'AnimatedVideoDownloadException(${failure.name}${detail == null ? '' : ': $detail'})';
}

/// A fully downloaded video, not yet published.
class DownloadedAnimatedVideo {
  const DownloadedAnimatedVideo({
    required this.file,
    required this.bytes,
    this.width,
    this.height,
  });

  final File file;
  final int bytes;
  final int? width;
  final int? height;
}

/// Fetches an Apple motion playlist into [output] as one complete MP4.
///
/// Only the single-file form is accepted: an init map plus byte-ranged
/// fragments that all point at one URI. Concatenating segmented playlists is
/// not safe for MP4 (a truncated segment can still remux "successfully"), so
/// those are reported as unsupported. The file is written in full before the
/// caller publishes it; [output] is removed on any failure.
Future<DownloadedAnimatedVideo> downloadAppleMotionVideo({
  required http.Client client,
  required Uri playlist,
  required File output,
  int maxBytes = kAnimatedArtworkMaxBytes,
  Duration deadline = const Duration(seconds: 60),
  bool Function()? isCancelled,
}) async {
  final stopwatch = Stopwatch()..start();
  void checkRunning() {
    if (isCancelled?.call() ?? false) {
      throw const AnimatedVideoDownloadException(AnimatedVideoFailure.cancelled);
    }
    if (stopwatch.elapsed > deadline) {
      throw const AnimatedVideoDownloadException(AnimatedVideoFailure.tooLarge, 'deadline');
    }
  }

  var complete = false;
  try {
    checkRunning();
    final top = await _readPlaylist(client, playlist, checkRunning);
    final variant = _avcVariant(top.text, top.uri);
    final dimensions = variant?.dimensions;
    if (dimensions != null &&
        (dimensions.$1 > kAnimatedArtworkMaxSide ||
            dimensions.$2 > kAnimatedArtworkMaxSide)) {
      throw const AnimatedVideoDownloadException(AnimatedVideoFailure.tooLarge, 'frame');
    }
    final media = variant == null
        ? top
        : await _readPlaylist(client, variant.uri, checkRunning);

    final single = _singleFileVideo(media.text, media.uri);
    if (single == null) {
      throw const AnimatedVideoDownloadException(AnimatedVideoFailure.unsupportedMedia);
    }
    if (single.length > maxBytes) {
      throw const AnimatedVideoDownloadException(AnimatedVideoFailure.tooLarge, 'bytes');
    }

    final request = http.Request('GET', single.uri);
    final response = await client.send(request).timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      await response.stream.drain<void>();
      throw AnimatedVideoDownloadException(
        AnimatedVideoFailure.network,
        'HTTP ${response.statusCode}',
      );
    }
    final declared = response.contentLength;
    if (declared != null && declared > maxBytes) {
      throw const AnimatedVideoDownloadException(AnimatedVideoFailure.tooLarge, 'declared');
    }

    final sink = output.openWrite();
    var written = 0;
    try {
      await for (final chunk in response.stream.timeout(
        const Duration(seconds: 15),
      )) {
        checkRunning();
        written += chunk.length;
        if (written > maxBytes) {
          throw const AnimatedVideoDownloadException(AnimatedVideoFailure.tooLarge, 'bytes');
        }
        sink.add(chunk);
      }
    } on TimeoutException {
      throw const AnimatedVideoDownloadException(AnimatedVideoFailure.network, 'stalled');
    } finally {
      await sink.close();
    }

    if (written < single.length ||
        (declared != null && declared >= 0 && written != declared)) {
      throw const AnimatedVideoDownloadException(AnimatedVideoFailure.incomplete);
    }
    await validateMp4(output);
    complete = true;
    return DownloadedAnimatedVideo(
      file: output,
      bytes: written,
      width: dimensions?.$1,
      height: dimensions?.$2,
    );
  } on AnimatedVideoDownloadException {
    rethrow;
  } on TimeoutException {
    throw const AnimatedVideoDownloadException(AnimatedVideoFailure.network, 'timeout');
  } on SocketException catch (error) {
    throw AnimatedVideoDownloadException(AnimatedVideoFailure.network, error.message);
  } on HttpException catch (error) {
    throw AnimatedVideoDownloadException(AnimatedVideoFailure.network, error.message);
  } on http.ClientException catch (error) {
    throw AnimatedVideoDownloadException(AnimatedVideoFailure.network, error.message);
  } on FormatException {
    throw const AnimatedVideoDownloadException(AnimatedVideoFailure.unsupportedMedia, 'playlist text');
  } finally {
    if (!complete && await output.exists()) {
      try {
        await output.delete();
      } on FileSystemException {
        // The staging folder is removed by its owner; nothing else to do.
      }
    }
  }
}

/// Copies a picked file into [output] from its byte stream, so content URIs
/// from the system picker work without assuming a filesystem path. The file
/// is validated before it is returned.
Future<DownloadedAnimatedVideo> importAnimatedVideoStream({
  required Stream<List<int>> source,
  required File output,
  int? declaredLength,
  int maxBytes = kAnimatedArtworkMaxBytes,
}) async {
  if (declaredLength != null && declaredLength > maxBytes) {
    throw const AnimatedVideoDownloadException(AnimatedVideoFailure.tooLarge, 'bytes');
  }
  var complete = false;
  var written = 0;
  final sink = output.openWrite();
  try {
    await for (final chunk in source) {
      written += chunk.length;
      if (written > maxBytes) {
        throw const AnimatedVideoDownloadException(AnimatedVideoFailure.tooLarge, 'bytes');
      }
      sink.add(chunk);
    }
    await sink.close();
    if (declaredLength != null && written != declaredLength) {
      throw const AnimatedVideoDownloadException(AnimatedVideoFailure.incomplete);
    }
    await validateMp4(output);
    complete = true;
    return DownloadedAnimatedVideo(file: output, bytes: written);
  } finally {
    if (!complete) {
      await sink.close().catchError((_) {});
      if (await output.exists()) await output.delete();
    }
  }
}

/// Checks that [file] starts with an `ftyp` box and contains a `moov` box.
/// This is a container check only; it does not decode the video.
Future<void> validateMp4(File file) async {
  final length = await file.length();
  if (length < 16) {
    throw const AnimatedVideoDownloadException(AnimatedVideoFailure.invalidContainer, 'short');
  }
  final raf = await file.open();
  try {
    final head = await raf.read(8);
    if (head.length < 8 || ascii.decode(head.sublist(4, 8)) != 'ftyp') {
      throw const AnimatedVideoDownloadException(AnimatedVideoFailure.invalidContainer, 'no ftyp');
    }
    await raf.setPosition(0);
    final marker = ascii.encode('moov');
    var tail = <int>[];
    var found = false;
    while (!found) {
      final chunk = await raf.read(64 * 1024);
      if (chunk.isEmpty) break;
      final window = [...tail, ...chunk];
      if (_indexOf(window, marker) >= 0) {
        found = true;
      } else {
        tail = window.sublist(window.length > 3 ? window.length - 3 : 0);
      }
    }
    if (!found) {
      throw const AnimatedVideoDownloadException(AnimatedVideoFailure.invalidContainer, 'no moov');
    }
  } finally {
    await raf.close();
  }
}

int _indexOf(List<int> haystack, List<int> needle) {
  outer:
  for (var i = 0; i <= haystack.length - needle.length; i++) {
    for (var j = 0; j < needle.length; j++) {
      if (haystack[i + j] != needle[j]) continue outer;
    }
    return i;
  }
  return -1;
}

class _Playlist {
  const _Playlist(this.uri, this.text);
  final Uri uri;
  final String text;
}

Future<_Playlist> _readPlaylist(
  http.Client client,
  Uri uri,
  void Function() checkRunning,
) async {
  checkRunning();
  final response = await client
      .send(http.Request('GET', uri))
      .timeout(const Duration(seconds: 15));
  if (response.statusCode != 200) {
    await response.stream.drain<void>();
    throw AnimatedVideoDownloadException(
      AnimatedVideoFailure.network,
      'HTTP ${response.statusCode}',
    );
  }
  final bytes = BytesBuilder(copy: false);
  await for (final chunk in response.stream.timeout(const Duration(seconds: 15))) {
    if (bytes.length + chunk.length > 512 * 1024) {
      throw const AnimatedVideoDownloadException(AnimatedVideoFailure.tooLarge, 'playlist');
    }
    bytes.add(chunk);
  }
  return _Playlist(uri, utf8.decode(bytes.takeBytes(), allowMalformed: false));
}

Uri? _resolve(Uri base, String? value) {
  if (value == null || value.isEmpty) return null;
  final uri = base.resolve(value);
  return uri.scheme == 'https' ? uri : null;
}

class _Variant {
  const _Variant(this.uri, this.dimensions);
  final Uri uri;
  final (int, int)? dimensions;
}

_Variant? _avcVariant(String playlist, Uri base) {
  var avc = false;
  (int, int)? dims;
  for (final raw in const LineSplitter().convert(playlist)) {
    final line = raw.trim();
    if (line.startsWith('#EXT-X-STREAM-INF:')) {
      avc = line.contains('avc1.') || line.contains('avc3.');
      final match = RegExp(r'RESOLUTION=(\d+)x(\d+)').firstMatch(line);
      dims = match == null
          ? null
          : (int.parse(match.group(1)!), int.parse(match.group(2)!));
    } else if (line.isNotEmpty && !line.startsWith('#')) {
      if (avc) {
        final uri = _resolve(base, line);
        if (uri != null) return _Variant(uri, dims);
      }
      avc = false;
      dims = null;
    }
  }
  return null;
}

class _SingleFile {
  const _SingleFile(this.uri, this.length);
  final Uri uri;
  final int length;
}

_SingleFile? _singleFileVideo(String playlist, Uri base) {
  final lines = const LineSplitter().convert(playlist).map((l) => l.trim()).toList();
  if (!lines.contains('#EXTM3U') || !lines.contains('#EXT-X-ENDLIST')) {
    return null;
  }
  Uri? video;
  var offset = 0;
  var segments = 0;
  String? range;
  for (final line in lines) {
    if (line.startsWith('#EXT-X-KEY:') &&
        !RegExp(r'(?:[:,])METHOD=NONE(?:,|$)').hasMatch(line)) {
      return null;
    }
    if (line.startsWith('#EXT-X-DISCONTINUITY') ||
        line.startsWith('#EXT-X-STREAM-INF:')) {
      return null;
    }
    if (line.startsWith('#EXT-X-MAP:')) {
      if (video != null || segments != 0) return null;
      video = _resolve(
        base,
        RegExp(r'(?:[:,])URI="([^"]+)"').firstMatch(line)?.group(1),
      );
      final initial = RegExp(r'(?:[:,])BYTERANGE="(\d+)@0"').firstMatch(line);
      offset = int.tryParse(initial?.group(1) ?? '') ?? 0;
      if (video == null || offset <= 0) return null;
    } else if (line.startsWith('#EXT-X-BYTERANGE:')) {
      if (range != null) return null;
      range = line.substring('#EXT-X-BYTERANGE:'.length);
    } else if (line.isNotEmpty && !line.startsWith('#')) {
      if (video == null || _resolve(base, line) != video || range == null) {
        return null;
      }
      final match = RegExp(r'^(\d+)(?:@(\d+))?$').firstMatch(range);
      final length = int.tryParse(match?.group(1) ?? '') ?? 0;
      final start = match?.group(2);
      if (length <= 0 || (start != null && int.tryParse(start) != offset)) {
        return null;
      }
      offset += length;
      range = null;
      segments++;
    }
  }
  if (video == null || segments == 0 || range != null) return null;
  return _SingleFile(video, offset);
}

