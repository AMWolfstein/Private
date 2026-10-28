import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistrum/models/settings.dart';
import 'package:sistrum/providers/library_collections_provider.dart';
import 'package:sistrum/providers/library_search_provider.dart';
import 'package:sistrum/providers/local_library_provider.dart';
import 'package:sistrum/providers/settings_provider.dart';
import 'package:sistrum/services/library_search.dart';

class _Settings extends SettingsNotifier {
  @override
  AppSettings build() => const AppSettings();
}

class _UnusedLibrary extends LocalLibraryNotifier {
  @override
  LocalLibraryState build() =>
      throw StateError('Disabled search read the index');
}

class _Collections extends LibraryCollectionsNotifier {
  @override
  LibraryCollectionsState build() => LibraryCollectionsState(
    playlists: [
      UserPlaylistCollection(
        id: 'mix',
        name: 'Local mix',
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
        tracks: const [],
      ),
    ],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  test('disabled local library still searches user playlists', () async {
    final container = ProviderContainer(
      overrides: [
        settingsProvider.overrideWith(_Settings.new),
        localLibraryProvider.overrideWith(_UnusedLibrary.new),
        libraryCollectionsProvider.overrideWith(_Collections.new),
      ],
    );
    addTearDown(container.dispose);
    final provider = librarySearchProvider((
      query: 'Local',
      kind: LibrarySearchKind.playlists,
      limit: 6,
      offset: 0,
    ));
    container.listen(provider, (_, _) {});
    expect((await container.read(provider.future)).map((hit) => hit.id), [
      'mix',
    ]);
  });
}
