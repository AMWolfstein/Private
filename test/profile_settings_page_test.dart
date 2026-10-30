import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/l10n/app_localizations.dart';
import 'package:sistrum/providers/user_profile_provider.dart';
import 'package:sistrum/screens/settings/profile_settings_page.dart';
import 'package:sistrum/services/platform/user_profile_store.dart';

/// Records the profile the page saves instead of writing it to disk.
class _FakeProfile extends UserProfileNotifier {
  final saved = <String>[];

  @override
  Future<UserProfile> build() async => const UserProfile(name: 'Ada');

  @override
  Future<void> save({
    required String name,
    dynamic photo,
    bool removePhoto = false,
  }) async {
    saved.add(name);
  }
}

void main() {
  testWidgets('the profile page shows the saved name for editing', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [userProfileProvider.overrideWith(_FakeProfile.new)],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const ProfileSettingsPage(profile: UserProfile(name: 'Ada')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Ada'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('saving sends the edited name to the profile store', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    late _FakeProfile fake;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          userProfileProvider.overrideWith(() => fake = _FakeProfile()),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const ProfileSettingsPage(profile: UserProfile(name: 'Ada')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final l10n = AppLocalizations.of(
      tester.element(find.byType(ProfileSettingsPage)),
    );
    await tester.enterText(find.byType(TextField), 'Grace');
    await tester.tap(find.text(l10n.dialogSave));
    await tester.pumpAndSettle();
    expect(fake.saved, ['Grace']);
    expect(tester.takeException(), isNull);
  });
}
