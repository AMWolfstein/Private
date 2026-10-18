import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotiflac_android/l10n/l10n.dart';
import 'package:spotiflac_android/models/track.dart';
import 'package:spotiflac_android/providers/library_collections_provider.dart';
import 'support/material_test_theme.dart';
import 'package:spotiflac_android/theme/mornye_theme.dart';
import 'package:spotiflac_android/widgets/track_detail_actions.dart';

const _track = Track(
  id: 'example-track',
  name: 'Example song',
  artistName: 'Example artist',
  albumName: 'Example album',
  duration: 180,
);

class _Collections extends LibraryCollectionsNotifier {
  var _batchCalls = 0;
  @override
  LibraryCollectionsState build() => LibraryCollectionsState(isLoaded: true);

  CollectionTrackEntry get _entry => CollectionTrackEntry(
    key: trackCollectionKey(_track),
    track: _track,
    addedAt: DateTime.utc(2026),
  );

  @override
  Future<({bool removed, int count})> toggleLovedTracks(
    Iterable<Track> tracks,
  ) async {
    _batchCalls++;
    final removed = state.loved.isNotEmpty;
    state = state.copyWith(loved: removed ? [] : [_entry]);
    return (removed: removed, count: 1);
  }
}

Widget _app(ProviderContainer container, Widget child, {bool mornye = false}) =>
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: mornye ? MornyeTheme.build(Brightness.light) : AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: child),
      ),
    );

void main() {
  for (final mornye in [false, true]) {
    testWidgets(
      'Love All action keeps its add/remove feedback in Mornye=$mornye',
      (tester) async {
        final collections = _Collections();
        final container = ProviderContainer(
          overrides: [
            libraryCollectionsProvider.overrideWith(() => collections),
          ],
        );
        addTearDown(container.dispose);
        await tester.pumpWidget(
          _app(
            container,
            Consumer(
              builder: (context, ref, _) => TextButton(
                onPressed: () => loveAllTracks(context, ref, [_track]),
                child: const Text('Apply'),
              ),
            ),
            mornye: mornye,
          ),
        );
        await tester.tap(find.text('Apply'));
        await tester.pumpAndSettle();
        final context = tester.element(find.text('Apply'));
        expect(
          find.text(context.l10n.snackbarAddedTracksToLoved(1)),
          findsOneWidget,
        );
        ScaffoldMessenger.of(context).removeCurrentSnackBar();
        await tester.pumpAndSettle();
        await tester.tap(find.text('Apply'));
        await tester.pumpAndSettle();
        expect(
          find.text(context.l10n.snackbarRemovedTracksFromLoved(1)),
          findsOneWidget,
        );
        expect(collections._batchCalls, 2);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
