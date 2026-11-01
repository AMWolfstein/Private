// Hand-maintained. Every locale with an arb file in lib/l10n/arb is supported.
// English is the template; the others are translations (machine-drafted and
// untranslated strings fall back to English). Keep this list in sync with the
// arb files and with appLanguageChoices in lib/constants/language_choices.dart.

import 'dart:ui' show PlatformDispatcher;
import 'package:flutter/widgets.dart';
import 'package:sistrum/l10n/app_localizations.dart';

/// Locales the app can run in. Names are kept for existing imports.
const List<Locale> filteredSupportedLocales = <Locale>[
  Locale('en'),
  Locale('ar'),
  Locale('de'),
  Locale('es'),
  Locale('es', 'ES'),
  Locale('fr'),
  Locale('hi'),
  Locale('id'),
  Locale('it'),
  Locale('ja'),
  Locale('ko'),
  Locale('nl'),
  Locale('pt'),
  Locale('pt', 'BR'),
  Locale('ru'),
  Locale('tr'),
  Locale('uk'),
  Locale('zh'),
  Locale('zh', 'CN'),
  Locale('zh', 'TW'),
];

/// Locale codes shown in the language picker (matches arb file suffixes).
const Set<String> filteredLocaleCodes = <String>{
  'en',
  'ar',
  'de',
  'es',
  'es_ES',
  'fr',
  'hi',
  'id',
  'it',
  'ja',
  'ko',
  'nl',
  'pt',
  'pt_BR',
  'ru',
  'tr',
  'uk',
  'zh',
  'zh_CN',
  'zh_TW',
};

/// Localized media-browser strings without a widget tree or Activity.
AppLocalizations appLocalizationsFor(String setting) {
  final parts = setting.replaceAll('-', '_').split('_');
  final requested = setting == 'system'
      ? PlatformDispatcher.instance.locale
      : Locale(parts.first, parts.length > 1 ? parts[1] : null);
  return lookupAppLocalizations(
    basicLocaleListResolution([requested], filteredSupportedLocales),
  );
}
