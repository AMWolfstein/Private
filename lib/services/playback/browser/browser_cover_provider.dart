// SPDX-License-Identifier: LGPL-3.0-only
// Copyright 2026 zarzet and contributors; adapted from Mornye v5.3.0.
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

class BrowserCoverProvider {
  const BrowserCoverProvider({required this.authority, required this.folders});

  final String authority;

  /// The folders the provider serves, by the name their URIs start with.
  final Map<String, String> folders;

  static const _channel = MethodChannel('com.amwolfstein.sistrum/covers');

  /// This app's cover provider, or null where there is none or it could
  /// not be reached.
  static Future<BrowserCoverProvider?> load() async {
    if (!Platform.isAndroid) return null;
    try {
      final info = await _channel.invokeMapMethod<String, Object?>('provider');
      final authority = info?['authority'];
      final folders = info?['folders'];
      if (authority is! String || folders is! Map) return null;
      return BrowserCoverProvider(
        authority: authority,
        folders: {
          for (final MapEntry(:key, :value) in folders.entries)
            if (key is String && value is String) key: value,
        },
      );
    } on Object {
      return null;
    }
  }

  /// The URI of the cover file [reference] names (an absolute path or a
  /// `file://` URI), the same for every form of one path. Null unless the
  /// file is directly in one of the [folders], as the provider serves
  /// nothing else.
  Uri? uriFor(String? reference) {
    final path = _localPath(reference);
    if (path == null) return null;
    final normalized = p.normalize(path);
    final name = p.basename(normalized);
    if (name.isEmpty || name.startsWith('.')) return null;
    final parent = p.dirname(normalized);
    for (final MapEntry(key: folder, value: directory) in folders.entries) {
      if (p.equals(parent, directory)) {
        return Uri(
          scheme: 'content',
          host: authority,
          pathSegments: [folder, name],
        );
      }
    }
    return null;
  }

  static String? _localPath(String? reference) {
    if (reference == null || reference.isEmpty) return null;
    if (p.isAbsolute(reference)) return reference;
    final uri = Uri.tryParse(reference);
    if (uri == null || !uri.isScheme('file')) return null;
    try {
      return uri.toFilePath();
    } on UnsupportedError {
      return null;
    }
  }
}
