import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sistrum/l10n/l10n.dart';
import 'package:sistrum/core/models/local_library_item.dart';
import 'package:sistrum/providers/local_library_provider.dart';
import 'package:sistrum/providers/library_tag_credits_provider.dart';
import 'package:sistrum/providers/playback_provider.dart';
import 'package:sistrum/services/library/browse/library_genres.dart';
import 'package:sistrum/services/library/browse/library_tag_credits.dart';
import 'package:sistrum/widgets/primitives/app_sliver_header.dart';
import 'package:sistrum/widgets/library/local_song_menu.dart';
import 'package:sistrum/widgets/library/local_song_row.dart';
import 'package:sistrum/utils/layout/nav_bar_inset.dart';
import 'package:sistrum/providers/library_database_provider.dart';

typedef GenrePageRequest = ({TagCreditField field, String? genre, int offset});
final genrePageLoaderProvider =
    Provider<Future<List<Map<String, dynamic>>> Function(GenrePageRequest)>((
      ref,
    ) {
      final version = ref.watch(
        localLibraryProvider.select((state) => state.loadedIndexVersion),
      );
      final credits = ref.watch(libraryTagCreditsCacheProvider);
      final rules = ref.watch(tagCreditRulesProvider);
      return (request) async =>
          LibraryGenres(
            await ref.read(libraryDatabaseProvider).database,
            credits: credits,
            rules: rules,
          ).page(
            field: request.field,
            genre: request.genre,
            offset: request.offset,
            libraryVersion: version,
          );
    });
final genrePageProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, GenrePageRequest>((ref, request) {
      ref.watch(
        localLibraryProvider.select((state) => state.loadedIndexVersion),
      );
      return ref.watch(genrePageLoaderProvider)(request);
    });

/// Genres, or the songs of one genre or composer. [field] picks which tag the
/// list and songs come from.
class LocalGenresScreen extends ConsumerStatefulWidget {
  const LocalGenresScreen({
    super.key,
    this.genre,
    this.name,
    this.field = TagCreditField.genre,
  });
  final String? genre, name;
  final TagCreditField field;
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
        genrePageProvider((
          field: widget.field,
          genre: widget.genre,
          offset: page * 40,
        )),
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
                        field: widget.field,
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
                    field: widget.field,
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
              child: Center(child: Text(context.l10n.libraryEmpty)),
            ),
          const NavBarSliverSpacer(),
        ],
      ),
    );
  }
}
