import 'dart:convert';
import 'dart:io';

const _androidStoragePathAliases = <String>[
  '/storage/emulated/0',
  '/storage/emulated/legacy',
  '/storage/self/primary',
  '/sdcard',
  '/mnt/sdcard',
];

const _maxPathMatchKeyCacheSize = 6000;
final Map<String, Set<String>> _pathMatchKeyCache = <String, Set<String>>{};

/// Windows drive paths are the only supported case-insensitive filesystem
/// spelling. Android/POSIX paths, `content://`, `file://` and other URIs are
/// case-sensitive: lowercasing them made `A.flac` and `a.flac` collide and
/// dropped the `#trackNN` fragment of SAF CUE rows.
final _windowsDrivePath = RegExp(r'^[A-Za-z]:[\\/]');

bool _isCaseInsensitivePath(String value) => _windowsDrivePath.hasMatch(value);

/// Path aliases that refer to the same physical file. The audio extension is
/// part of the identity: two files that differ only by extension are
/// different files.
Set<String> buildPathMatchKeys(String? filePath) {
  final cleaned = filePath?.trim() ?? '';
  if (cleaned.isEmpty) return const {};
  final cached = _pathMatchKeyCache.remove(cleaned);
  if (cached != null) {
    _pathMatchKeyCache[cleaned] = cached;
    return cached;
  }
  final result = Set<String>.unmodifiable(_computePathMatchKeys(cleaned));
  _pathMatchKeyCache[cleaned] = result;
  while (_pathMatchKeyCache.length > _maxPathMatchKeyCacheSize) {
    _pathMatchKeyCache.remove(_pathMatchKeyCache.keys.first);
  }
  return result;
}

bool physicalFilePathsMatch(String? first, String? second) {
  final firstKeys = buildPathMatchKeys(first);
  if (firstKeys.isEmpty) return false;
  return buildPathMatchKeys(second).any((key) => firstKeys.contains(key));
}

bool isPhysicalFileRetained(
  String? candidatePath,
  Iterable<String?> retainedPaths,
) => retainedPaths.any(
  (retainedPath) => physicalFilePathsMatch(candidatePath, retainedPath),
);

Set<String> _computePathMatchKeys(String cleaned) {
  final keys = <String>{};
  final visited = <String>{};

  // A DocumentsProvider document can be reached through an album tree, its
  // parent tree, or a direct document URI. Keep that identity independent of
  // the selected tree, without guessing from a filename or lowercasing the
  // provider's opaque document ID. Parse only the original URI: decoding it
  // repeatedly would change IDs containing literal percent escapes.
  final documentKey = _androidDocumentMatchKey(Uri.tryParse(cleaned));
  if (documentKey != null) keys.add(documentKey);

  void addNormalized(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return;
    if (!visited.add(trimmed)) return;

    keys.add(trimmed);
    if (_isCaseInsensitivePath(trimmed)) {
      keys.add(trimmed.toLowerCase());
    }

    if (trimmed.contains('\\')) {
      final slash = trimmed.replaceAll('\\', '/');
      if (slash != trimmed) {
        addNormalized(slash);
      }
    }

    if (trimmed.contains('%')) {
      try {
        final decoded = Uri.decodeFull(trimmed);
        if (decoded != trimmed) {
          addNormalized(decoded);
        }
      } catch (_) {}
    }

    Uri? parsed;
    try {
      parsed = Uri.parse(trimmed);
    } catch (_) {}

    if (parsed != null && parsed.hasScheme) {
      // Keep the query and fragment: SAF CUE virtual tracks carry `#trackNN`
      // in the fragment, and dropping it makes every track of a sheet share a
      // key. `parsed.toString()` also normalizes the authority to lower case.
      final uriString = parsed.toString();
      keys.add(uriString);
      if (_isCaseInsensitivePath(uriString)) {
        keys.add(uriString.toLowerCase());
      }

      if (parsed.scheme == 'file') {
        try {
          addNormalized(parsed.toFilePath());
        } catch (_) {}
      }

      for (final alias in _androidExternalStorageDocumentPaths(parsed)) {
        addNormalized(alias);
      }
    } else if (trimmed.startsWith('/')) {
      try {
        keys.add(Uri.file(trimmed).toString());
      } catch (_) {}
    }

    if (Platform.isAndroid) {
      for (final alias in _androidEquivalentPaths(trimmed)) {
        if (alias != trimmed) {
          addNormalized(alias);
        }
      }
    }
  }

  addNormalized(cleaned);

  return keys;
}

String? _androidDocumentMatchKey(Uri? uri) {
  if (uri == null || uri.scheme != 'content' || uri.authority.isEmpty) {
    return null;
  }
  final segments = uri.pathSegments;
  final isDirect = segments.length == 2 && segments[0] == 'document';
  final isTreeDocument =
      segments.length == 4 &&
      segments[0] == 'tree' &&
      segments[1].isNotEmpty &&
      segments[2] == 'document';
  if ((!isDirect && !isTreeDocument) || segments.last.isEmpty) return null;
  // Encode only the authority so the separator cannot be ambiguous. The ID
  // stays verbatim, extension included.
  final authority = base64Url.encode(utf8.encode(uri.authority.toLowerCase()));
  final fragment = uri.fragment;
  final suffix = fragment.isEmpty ? '' : '#$fragment';
  return 'saf-document:$authority:${segments.last}$suffix';
}

Iterable<String> _androidExternalStorageDocumentPaths(Uri uri) {
  if (uri.scheme.toLowerCase() != 'content' ||
      uri.host.toLowerCase() != 'com.android.externalstorage.documents') {
    return const [];
  }
  // A fragment marks a virtual SAF CUE track (`#trackNN`). It is not part of
  // the backing document's filesystem path: a raw alias would make every track
  // of the sheet collide with the CUE file, so do not derive one.
  if (uri.hasFragment) return const [];

  final segments = uri.pathSegments;
  final documentIndex = segments.lastIndexOf('document');
  final treeIndex = segments.lastIndexOf('tree');
  final idIndex = documentIndex >= 0 ? documentIndex + 1 : treeIndex + 1;
  if (idIndex <= 0 || idIndex >= segments.length) return const [];

  final documentId = segments.sublist(idIndex).join('/');
  final separator = documentId.indexOf(':');
  if (separator < 0 ||
      documentId.substring(0, separator).toLowerCase() != 'primary') {
    return const [];
  }

  final relativePath = documentId
      .substring(separator + 1)
      .replaceAll('\\', '/')
      .replaceFirst(RegExp(r'^/+'), '');
  final suffix = relativePath.isEmpty ? '' : '/$relativePath';
  return _androidStoragePathAliases.map((prefix) => '$prefix$suffix');
}

Iterable<String> _androidEquivalentPaths(String path) {
  final normalized = path.replaceAll('\\', '/');
  final lower = normalized.toLowerCase();
  String? suffix;

  for (final prefix in _androidStoragePathAliases) {
    if (lower == prefix) {
      suffix = '';
      break;
    }
    final withSlash = '$prefix/';
    if (lower.startsWith(withSlash)) {
      suffix = normalized.substring(prefix.length);
      break;
    }
  }

  if (suffix == null) return const [];
  return _androidStoragePathAliases.map((prefix) => '$prefix$suffix');
}
