import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spotiflac_android/l10n/l10n.dart';
import 'package:spotiflac_android/providers/local_library_provider.dart';
import 'package:spotiflac_android/providers/playback_provider.dart';
import 'package:spotiflac_android/providers/settings_provider.dart';
import 'package:spotiflac_android/services/library_database.dart';
import 'package:spotiflac_android/services/library_genres.dart';
import 'package:spotiflac_android/widgets/app_sliver_header.dart';
import 'package:spotiflac_android/widgets/local_song_menu.dart';
import 'package:spotiflac_android/widgets/local_song_row.dart';
import 'package:spotiflac_android/utils/nav_bar_inset.dart';

typedef GenrePageRequest = ({String? genre, int offset});
final genrePageLoaderProvider =
    Provider<Future<List<Map<String, dynamic>>> Function(GenrePageRequest)>(
      (ref) =>
          (request) async => LibraryGenres(
            await LibraryDatabase.instance.database,
          ).page(genre: request.genre, offset: request.offset),
    );
final genrePageProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, GenrePageRequest>((ref, request) {
      ref.watch(
        localLibraryProvider.select((state) => state.loadedIndexVersion),
      );
      if (!ref.watch(
        settingsProvider.select((state) => state.localLibraryEnabled),
      )) {
        return [];
      }
      return ref.watch(genrePageLoaderProvider)(request);
    });

class LocalGenresScreen extends ConsumerStatefulWidget {
  const LocalGenresScreen({super.key, this.genre, this.name});
  final String? genre, name;
  @override
  ConsumerState<LocalGenresScreen> createState() => _LocalGenresScreenState();
}

class _LocalGenresScreenState extends ConsumerState<LocalGenresScreen> {
  final _scroll = ScrollController();
  int _pages = 1;
  int? _revision;
  bool _loading = true, _hasMore = true;
  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.extentAfter < 500 && !_loading && _hasMore) {
        setState(() => _pages++);
      }
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final revision = ref.watch(
      localLibraryProvider.select((state) => state.loadedIndexVersion),
    );
    if (_revision != revision) {
      _revision = revision;
      _pages = 1;
    }
    final entries = <Map<String, dynamic>>[];
    AsyncValue<List<Map<String, dynamic>>>? last;
    for (var page = 0; page < _pages; page++) {
      final value = ref.watch(
        genrePageProvider((genre: widget.genre, offset: page * 40)),
      );
      last = value;
      entries.addAll(value.asData?.value ?? []);
    }
    final current = last!;
    _loading = current.isLoading;
    _hasMore = (current.asData?.value.length ?? 0) == 40;
    final tracks = widget.genre == null
        ? <LocalLibraryItem>[]
        : entries.map(LocalLibraryItem.fromJson).toList();
    return Scaffold(
      body: CustomScrollView(
        controller: _scroll,
        slivers: [
          AppSliverHeader.page(
            title: widget.name ?? context.l10n.libraryGenres,
          ),
          SliverList.builder(
            itemCount: entries.length,
            itemBuilder: (context, index) {
              final row = entries[index];
              if (widget.genre == null) {
                return ListTile(
                  leading: const Icon(Icons.category_outlined),
                  title: Text(row['name'] as String),
                  subtitle: Text(
                    context.l10n.tracksCount(
                      (row['track_count'] as num).toInt(),
                    ),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => LocalGenresScreen(
                        genre: row['genre_key'] as String,
                        name: row['name'] as String,
                      ),
                    ),
                  ),
                );
              }
              final track = tracks[index];
              return LocalSongRow(
                title: track.trackName,
                artist: track.artistName,
                cover: track.coverPath,
                explicit: track.explicit,
                onPlay: () => ref
                    .read(playbackProvider.notifier)
                    .playLocalLibraryQueue(tracks, startItem: track),
                onMenu: (anchor) =>
                    showLocalSongMenu(context, ref, track, anchor: anchor),
              );
            },
          ),
          if (_loading)
            const SliverToBoxAdapter(
              child: Center(child: CircularProgressIndicator()),
            ),
          if (current.hasError)
            SliverToBoxAdapter(
              child: TextButton(
                onPressed: () => ref.invalidate(
                  genrePageProvider((
                    genre: widget.genre,
                    offset: (_pages - 1) * 40,
                  )),
                ),
                child: Text(context.l10n.dialogRetry),
              ),
            ),
          if (!_loading && !current.hasError && entries.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: Text(context.l10n.queueEmptyHistory)),
            ),
          const NavBarSliverSpacer(),
        ],
      ),
    );
  }
}
