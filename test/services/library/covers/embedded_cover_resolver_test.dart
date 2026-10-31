import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/services/library/covers/embedded_cover_resolver.dart';

part 'embedded_cover_resolver_1.dart';
part 'embedded_cover_resolver_2.dart';

void main() {
  _registerEmbeddedCoverResolver1();
  _registerEmbeddedCoverResolver2();
}
