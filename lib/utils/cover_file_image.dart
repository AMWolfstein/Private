import 'dart:io';

import 'package:flutter/painting.dart';

/// The file image for a cover path, accepting `file://` URIs as well.
FileImage cachedCoverImageProvider(String path) => FileImage(
  File(path.startsWith('file://') ? Uri.parse(path).toFilePath() : path),
);
