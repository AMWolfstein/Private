import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/services/library/covers/embedded_cover_resolver.dart';

part 'embedded_cover_resolver_extraction.dart';
part 'embedded_cover_resolver_cache.dart';

void main() {
  _registerEmbeddedCoverResolverExtraction();
  _registerEmbeddedCoverResolverCache();
}
