import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistrum/core/constants/language_choices.dart';
import 'package:sistrum/l10n/l10n.dart';
import 'package:sistrum/core/models/app_glass.dart';
import 'package:sistrum/core/models/settings.dart';
import 'package:sistrum/core/models/theme_settings.dart';
import 'package:sistrum/providers/runtime_profile_provider.dart';
import 'package:sistrum/providers/settings/theme_provider.dart';
import 'package:sistrum/screens/settings/appearance/appearance_settings_page.dart';
import 'package:sistrum/app.dart';
import 'package:sistrum/core/theme/app_theme.dart';

part 'appearance_settings_1.dart';
part 'appearance_settings_2.dart';
part 'appearance_settings_3.dart';

void main() {
  _registerAppearanceSettings1();
  _registerAppearanceSettings2();
  _registerAppearanceSettings3();
}
