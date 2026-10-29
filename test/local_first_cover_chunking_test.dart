import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistrum/providers/local_library_provider.dart';
import 'package:sistrum/providers/local_library_cover_providers.dart';

/// OPT-PERF-006: the first-cover lookup resolves the batch in ordered 450-key
/// chunks and stops at the first chunk that yields a usable cover.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('stops at the first chunk with a cover and preserves order', () async {
    SharedPreferences.setMockInitialValues({});
    final chunkSizes = <int>[];
    final container = ProviderContainer(
      overrides: [
        localLibraryProvider.overrideWith(_Library.new),
        libraryExistingBatchLoaderProvider.overrideWithValue((requests) async {
          chunkSizes.add(requests.length);
          if (chunkSizes.length == 1) {
            // Second row of the first chunk has the cover.
            return [null, const {'coverPath': '/covers/first.jpg'}];
          }
          return List.filled(requests.length, null);
        }),
      ],
    );
    addTearDown(container.dispose);
    final provider = localLibraryFirstCoverProvider(
      LocalLibraryCoverBatchRequest([
        for (var i = 0; i < 1000; i++)
          LocalLibraryCoverRequest(
            isrc: null,
            trackName: 'Track $i',
            artistName: 'Artist',
          ),
      ]),
    );
    expect(await container.read(provider.future), '/covers/first.jpg');
    expect(chunkSizes, [450]);
  });

  test('chunks the whole batch when no cover exists', () async {
    SharedPreferences.setMockInitialValues({});
    final chunkSizes = <int>[];
    final container = ProviderContainer(
      overrides: [
        localLibraryProvider.overrideWith(_Library.new),
        libraryExistingBatchLoaderProvider.overrideWithValue((requests) async {
          chunkSizes.add(requests.length);
          return List.filled(requests.length, null);
        }),
      ],
    );
    addTearDown(container.dispose);
    final provider = localLibraryFirstCoverProvider(
      LocalLibraryCoverBatchRequest([
        for (var i = 0; i < 1000; i++)
          LocalLibraryCoverRequest(
            isrc: null,
            trackName: 'Track $i',
            artistName: 'Artist',
          ),
      ]),
    );
    expect(await container.read(provider.future), isNull);
    expect(chunkSizes, [450, 450, 100]);
  });
}

class _Library extends LocalLibraryNotifier {
  @override
  LocalLibraryState build() => LocalLibraryState();
}
