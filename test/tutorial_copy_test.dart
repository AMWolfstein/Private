import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotiflac_android/l10n/app_localizations.dart';

void main() {
  group('unified guide copy', () {
    test('uses the current app name and local workflow', () {
      for (final locale in AppLocalizations.supportedLocales) {
        final strings = lookupAppLocalizations(locale);
        final setupTagline = strings.setupLocalPlayback.toLowerCase();
        final searchDescription = strings.tutorialSearchDesc.toLowerCase();

        expect(
          strings.appName,
          contains('SpotiFLAC'),
          reason: 'Unexpected app name for $locale',
        );
        expect(
          setupTagline,
          isNot(contains('spotify')),
          reason: 'Provider-specific setup tagline for $locale',
        );
        expect(
          searchDescription,
          isNot(anyOf(contains('spotify'), contains('deezer'))),
          reason: 'Provider-specific guide text for $locale',
        );
      }
    });

    test('English and Indonesian describe the current feature set', () {
      final english = lookupAppLocalizations(const Locale('en'));
      final indonesian = lookupAppLocalizations(const Locale('id'));

      expect(english.setupLocalPlayback, contains('offline'));
      expect(english.tutorialLibraryTip2, contains('built-in player'));
      expect(indonesian.setupLocalPlayback, contains('offline'));
      expect(indonesian.tutorialLibraryTip2, contains('pemutar bawaan'));
    });
  });
}
