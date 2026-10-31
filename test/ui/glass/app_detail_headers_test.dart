import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/providers/library/cover_palette_provider.dart';
import 'package:sistrum/services/library/covers/cover_palette.dart';
import 'package:sistrum/core/theme/app_theme.dart';
import 'package:sistrum/widgets/collection/collection_scaffold.dart';
import 'package:sistrum/widgets/glass/artwork/app_artwork_page_ground.dart';
import 'package:sistrum/widgets/header/album_detail_header.dart';
import 'package:sistrum/widgets/header/album_play_actions.dart';
import 'package:sistrum/widgets/header/app_artist_header.dart';
import 'package:sistrum/widgets/header/header_controls.dart';

part 'app_detail_headers_1.dart';
part 'app_detail_headers_2.dart';

void main() {
  _registerAppDetailHeaders1();
  _registerAppDetailHeaders2();
}
