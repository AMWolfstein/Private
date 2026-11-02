import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:sistrum/services/lyrics/lrclib_lyrics_provider.dart';
import 'package:sistrum/services/lyrics/lyrics_converters.dart';
import 'package:sistrum/services/lyrics/lyrics_matching.dart';
import 'package:sistrum/services/lyrics/online_lyrics_search.dart';

/// Shared GET for the online sources. A non-200 status throws, except 404
/// which the caller reads as "no lyrics for this song".
class LyricsHttpGet {
  LyricsHttpGet(this._client, {this.headers = const {}});

  final http.Client _client;
  final Map<String, String> headers;
  static const _timeout = Duration(seconds: 12);

  Future<http.Response?> call(Uri uri, {Map<String, String>? extra}) async {
    final response = await _client
        .get(uri, headers: {...headers, ...?extra})
        .timeout(_timeout);
    if (response.statusCode == 404) return null;
    if (response.statusCode != 200) {
      throw http.ClientException('HTTP ${response.statusCode}', uri);
    }
    return response;
  }

  Future<Object?> json(Uri uri, {Map<String, String>? extra}) async {
    final response = await call(uri, extra: extra);
    if (response == null) return null;
    return jsonDecode(utf8.decode(response.bodyBytes));
  }
}

/// A candidate with a body that could not be converted is "no lyrics", not a
/// failed source. Network and status errors still propagate. [title], [artist]
/// and [duration] describe the song the source matched, when it reports them.
OnlineLyricsCandidate? _candidate(
  String provider,
  String Function() convert, {
  String? title,
  String? artist,
  double? duration,
}) {
  final String text;
  try {
    text = convert();
  } on LyricsFormatException {
    return null;
  }
  if (text.trim().isEmpty) return null;
  return OnlineLyricsCandidate(
    provider: provider,
    timing: LyricsTiming.detect(text),
    text: text,
    title: title,
    artist: artist,
    durationSeconds: duration,
  );
}

String _paxQuery(OnlineLyricsQuery q) => '${q.title} ${q.artist}'.trim();

Map<String, dynamic>? _asMap(Object? value) =>
    value is Map<String, dynamic> ? value : null;

Iterable<Map<String, dynamic>> _maps(Object? value) =>
    value is List ? value.whereType<Map<String, dynamic>>() : const [];

const _paxBase = 'https://lyrics.paxsenix.org';

// ---------------------------------------------------------------------------
// Word-capable sources. Each may return word timing, or only lines or plain
// text when the match has no word timing; the result is classified from its text.
// ---------------------------------------------------------------------------

/// Spotify through the Paxsenix proxy, searched by title and artist.
class SpotifyLyricsProvider implements OnlineLyricsProvider {
  SpotifyLyricsProvider(this._get);
  final LyricsHttpGet _get;

  @override
  String get id => 'spotify';

  @override
  Future<OnlineLyricsCandidate?> find(OnlineLyricsQuery query) async {
    final search = await _get.json(
      Uri.parse(
        '$_paxBase/spotify/search',
      ).replace(queryParameters: {'q': _paxQuery(query)}),
    );
    final song = _maps(search).firstWhere(
      (song) => songMatches(
        wantedTitle: query.title,
        wantedArtist: query.artist,
        wantedDuration: query.durationSeconds,
        foundTitle: song['name']?.toString() ?? '',
        foundArtist: song['artistName']?.toString() ?? '',
        foundDuration: parseClockSeconds(song['duration']?.toString()),
      ),
      orElse: () => <String, dynamic>{},
    );
    final trackId = song['trackId']?.toString() ?? '';
    if (trackId.isEmpty) return null;
    final body = await _get.call(
      Uri.parse(
        '$_paxBase/spotify/lyrics',
      ).replace(queryParameters: {'id': trackId}),
    );
    if (body == null) return null;
    return _candidate(
      id,
      () => parseProxyPayload(utf8.decode(body.bodyBytes)),
      title: song['name']?.toString(),
      artist: song['artistName']?.toString(),
      duration: parseClockSeconds(song['duration']?.toString()),
    );
  }
}

/// Deezer lyrics. The track is found by its ISRC on the public Deezer API,
/// so a song without one is not searched by title here.
class DeezerLyricsProvider implements OnlineLyricsProvider {
  DeezerLyricsProvider(this._get);
  final LyricsHttpGet _get;

  @override
  String get id => 'deezer';

  @override
  Future<OnlineLyricsCandidate?> find(OnlineLyricsQuery query) async {
    final isrc = query.isrc?.trim().toUpperCase() ?? '';
    if (isrc.length != 12) return null;
    final track = _asMap(
      await _get.json(Uri.parse('https://api.deezer.com/2.0/track/isrc:$isrc')),
    );
    final deezerId = track?['id'];
    if (deezerId == null) return null;
    final body = await _get.call(
      Uri.parse(
        '$_paxBase/deezer/lyrics',
      ).replace(queryParameters: {'id': '$deezerId'}),
    );
    if (body == null) return null;
    return _candidate(
      id,
      () => parseProxyPayload(utf8.decode(body.bodyBytes)),
      title: track?['title']?.toString(),
      artist: _asMap(track?['artist'])?['name']?.toString(),
      duration: (track?['duration'] as num?)?.toDouble(),
    );
  }
}

/// YouTube: the video title must contain the song title and either the
/// artist's name or the channel must be the artist.
class YouTubeLyricsProvider implements OnlineLyricsProvider {
  YouTubeLyricsProvider(this._get);
  final LyricsHttpGet _get;

  @override
  String get id => 'youtube';

  @override
  Future<OnlineLyricsCandidate?> find(OnlineLyricsQuery query) async {
    final search = await _get.json(
      Uri.parse(
        '$_paxBase/youtube/search',
      ).replace(queryParameters: {'q': _paxQuery(query)}),
    );
    final wantedTitle = normalizeTitle(query.title);
    final video = _maps(search).firstWhere((video) {
      final title = normalizeTitle(video['title']?.toString() ?? '');
      final author = video['author']?.toString() ?? '';
      final titleHasArtist = artistWords(
        query.artist,
      ).every((word) => title.contains(word));
      return wantedTitle.isNotEmpty &&
          title.contains(wantedTitle) &&
          (artistsMatch(query.artist, author) || titleHasArtist) &&
          durationsMatch(
            query.durationSeconds,
            parseClockSeconds(video['duration']?.toString()),
          );
    }, orElse: () => <String, dynamic>{});
    final videoId = video['videoId']?.toString() ?? '';
    if (videoId.isEmpty) return null;
    final body = await _get.call(
      Uri.parse(
        '$_paxBase/youtube/lyrics',
      ).replace(queryParameters: {'id': videoId}),
    );
    if (body == null) return null;
    return _candidate(
      id,
      () => parseProxyPayload(utf8.decode(body.bodyBytes)),
      title: video['title']?.toString(),
      artist: video['author']?.toString(),
      duration: parseClockSeconds(video['duration']?.toString()),
    );
  }
}

/// Musixmatch's word-timed lyrics through the Paxsenix proxy.
class MusixmatchLyricsProvider implements OnlineLyricsProvider {
  MusixmatchLyricsProvider(this._get);
  final LyricsHttpGet _get;

  @override
  String get id => 'musixmatch';

  @override
  Future<OnlineLyricsCandidate?> find(OnlineLyricsQuery query) async {
    if (query.title.trim().isEmpty || query.artist.trim().isEmpty) return null;
    final params = {
      't': query.title,
      'a': query.artist,
      'type': 'word',
      'format': 'lrc',
      if (query.durationSeconds != null && query.durationSeconds! > 0)
        'd': query.durationSeconds!.round().toString(),
    };
    final body = await _get.call(
      Uri.parse('$_paxBase/musixmatch/lyrics').replace(queryParameters: params),
    );
    if (body == null) return null;
    return _candidate(
      id,
      () => parseProxyPayload(utf8.decode(body.bodyBytes)),
      title: query.title,
      artist: query.artist,
      duration: query.durationSeconds,
    );
  }
}

/// LyricsPlus (KPOE). Tries the ISRC first, then retries without it.
class LyricsPlusProvider implements OnlineLyricsProvider {
  LyricsPlusProvider(this._get);
  final LyricsHttpGet _get;

  static const _servers = [
    'https://lyricsplus.prjktla.my.id/v2/lyrics/get',
    'https://lyricsplus.binimum.org/v2/lyrics/get',
  ];

  @override
  String get id => 'lyricsplus';

  @override
  Future<OnlineLyricsCandidate?> find(OnlineLyricsQuery query) async {
    if (query.title.trim().isEmpty || query.artist.trim().isEmpty) return null;
    for (final server in _servers) {
      final candidate = await _ask(server, query, query.isrc);
      if (candidate != null) return candidate;
    }
    return null;
  }

  Future<OnlineLyricsCandidate?> _ask(
    String server,
    OnlineLyricsQuery query,
    String? isrc,
  ) async {
    final params = {
      'title': query.title,
      'artist': query.artist,
      if (query.durationSeconds != null && query.durationSeconds! > 0)
        'duration': query.durationSeconds!.toStringAsFixed(3),
      if (isrc != null && isrc.trim().isNotEmpty) 'isrc': isrc.trim(),
    };
    final response = await _get.call(
      Uri.parse(server).replace(queryParameters: params),
    );
    if (response == null) {
      // A miss with an ISRC may still match by title on the same server.
      if (isrc != null && isrc.trim().isNotEmpty) {
        return _ask(server, query, null);
      }
      return null;
    }
    return _candidate(
      id,
      () {
        final json = jsonDecode(utf8.decode(response.bodyBytes));
        if (json is! Map<String, dynamic>) {
          throw const LyricsFormatException('not an object');
        }
        return formatKpoe(json);
      },
      title: query.title,
      artist: query.artist,
      duration: query.durationSeconds,
    );
  }
}

/// BetterLyrics: a keyless cache that returns Apple TTML.
class BetterLyricsProvider implements OnlineLyricsProvider {
  BetterLyricsProvider(this._get);
  final LyricsHttpGet _get;

  @override
  String get id => 'betterlyrics';

  @override
  Future<OnlineLyricsCandidate?> find(OnlineLyricsQuery query) async {
    if (query.title.trim().isEmpty || query.artist.trim().isEmpty) return null;
    final params = {
      's': query.title.trim(),
      'a': query.artist.trim(),
      if (query.durationSeconds != null && query.durationSeconds! > 0)
        'd': query.durationSeconds!.round().toString(),
    };
    final json = _asMap(
      await _get.json(
        Uri.parse(
          'https://lyrics-api.boidu.dev/getLyrics',
        ).replace(queryParameters: params),
      ),
    );
    final ttml = json?['ttml']?.toString() ?? '';
    if (ttml.trim().isEmpty) return null;
    return _candidate(
      id,
      () => formatTtml(ttml),
      title: query.title,
      artist: query.artist,
      duration: query.durationSeconds,
    );
  }
}

/// lrc.red: searched by title and artist, then fetched by ISRC as TTML.
class LrcRedLyricsProvider implements OnlineLyricsProvider {
  LrcRedLyricsProvider(this._get);
  final LyricsHttpGet _get;

  @override
  String get id => 'lrcred';

  @override
  Future<OnlineLyricsCandidate?> find(OnlineLyricsQuery query) async {
    final search = _asMap(
      await _get.json(
        Uri.parse(
          'https://lrc.red/search.json',
        ).replace(queryParameters: {'q': _paxQuery(query)}),
      ),
    );
    final hit = _maps(search?['hits']).firstWhere((hit) {
      final isrc = hit['isrc']?.toString() ?? '';
      return _isIsrc(isrc) &&
          songMatches(
            wantedTitle: query.title,
            wantedArtist: query.artist,
            wantedDuration: query.durationSeconds,
            foundTitle: hit['title']?.toString() ?? '',
            foundArtist: hit['artist']?.toString() ?? '',
            foundDuration: (hit['duration'] as num?)?.toDouble(),
          );
    }, orElse: () => <String, dynamic>{});
    final isrc = hit['isrc']?.toString().toUpperCase() ?? '';
    if (!_isIsrc(isrc)) return null;
    final body = await _get.call(Uri.parse('https://lrc.red/s/$isrc.ttml'));
    if (body == null) return null;
    return _candidate(
      id,
      () => formatTtml(utf8.decode(body.bodyBytes)),
      title: hit['title']?.toString(),
      artist: hit['artist']?.toString(),
      duration: (hit['duration'] as num?)?.toDouble(),
    );
  }

  static bool _isIsrc(String value) =>
      RegExp(r'^[A-Z0-9]{12}$').hasMatch(value.toUpperCase());
}

/// Apple Music. The catalog search needs a web token scraped from the public
/// web player; the lyrics come from the Paxsenix proxy. Apple's token can
/// expire, in which case this source reports "no lyrics" rather than failing.
class AppleLyricsProvider implements OnlineLyricsProvider {
  AppleLyricsProvider(this._get, {required this.zarz});
  final LyricsHttpGet _get;
  final bool zarz;

  static final _indexScript = RegExp(r'''/assets/index~[^"' <]+\.js''');
  static final _token = RegExp(
    r'eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+',
  );

  @override
  String get id => zarz ? 'zarz' : 'apple_music';

  @override
  Future<OnlineLyricsCandidate?> find(OnlineLyricsQuery query) async {
    final match = await _songId(query);
    if (match == null) return null;
    final songId = match.id;
    final uri = zarz
        ? Uri.parse(
            'https://api.zarz.moe/apple-music/lyrics',
          ).replace(queryParameters: {'id': songId, 'v': '1'})
        : Uri.parse(
            '$_paxBase/apple-music/lyrics',
          ).replace(queryParameters: {'id': songId});
    final body = await _get.call(uri);
    if (body == null) return null;
    return _candidate(
      id,
      () => parseProxyPayload(utf8.decode(body.bodyBytes)),
      title: match.title,
      artist: match.artist,
      duration: match.duration,
    );
  }

  Future<({String id, String? title, String? artist, double? duration})?>
  _songId(OnlineLyricsQuery query) async {
    final page = await _get.call(Uri.parse('https://beta.music.apple.com'));
    if (page == null) return null;
    final script = _indexScript.firstMatch(utf8.decode(page.bodyBytes));
    if (script == null) return null;
    final js = await _get.call(
      Uri.parse('https://beta.music.apple.com${script.group(0)}'),
    );
    final token = _token
        .firstMatch(js == null ? '' : utf8.decode(js.bodyBytes))
        ?.group(0);
    if (token == null) return null;
    final response = await _get.call(
      Uri.parse('https://amp-api.music.apple.com/v1/catalog/us/search').replace(
        queryParameters: {
          'term': _paxQuery(query),
          'types': 'songs',
          'limit': '25',
          'l': 'en-US',
          'platform': 'web',
          'format[resources]': 'map',
          'include[songs]': 'artists',
          'extend': 'artistUrl',
        },
      ),
      extra: {
        'Authorization': 'Bearer $token',
        'Origin': 'https://music.apple.com',
        'Referer': 'https://music.apple.com/',
      },
    );
    if (response == null) return null;
    final json = _asMap(jsonDecode(utf8.decode(response.bodyBytes)));
    final songsData = _maps(
      _asMap(_asMap(json?['results'])?['songs'])?['data'],
    );
    final ids = songsData
        .map((song) => song['id']?.toString() ?? '')
        .where((id) => id.isNotEmpty);
    final resources = _asMap(_asMap(json?['resources'])?['songs']);
    for (final songId in ids) {
      final attributes = _asMap(_asMap(resources?[songId])?['attributes']);
      if (attributes == null) continue;
      if (songMatches(
        wantedTitle: query.title,
        wantedArtist: query.artist,
        wantedDuration: query.durationSeconds,
        foundTitle: attributes['name']?.toString() ?? '',
        foundArtist: attributes['artistName']?.toString() ?? '',
        foundDuration:
            ((attributes['durationInMillis'] as num?)?.toDouble() ?? 0) / 1000,
      )) {
        return (
          id: songId,
          title: attributes['name']?.toString(),
          artist: attributes['artistName']?.toString(),
          duration:
              ((attributes['durationInMillis'] as num?)?.toDouble() ?? 0) /
              1000,
        );
      }
    }
    return null;
  }
}

// ---------------------------------------------------------------------------
// Line-synced sources.
// ---------------------------------------------------------------------------

/// Netease through the Paxsenix proxy: line-timed LRC.
class NeteaseLyricsProvider implements OnlineLyricsProvider {
  NeteaseLyricsProvider(this._get);
  final LyricsHttpGet _get;

  @override
  String get id => 'netease';

  @override
  Future<OnlineLyricsCandidate?> find(OnlineLyricsQuery query) async {
    final search = _asMap(
      await _get.json(
        Uri.parse(
          '$_paxBase/netease/search',
        ).replace(queryParameters: {'q': _paxQuery(query)}),
      ),
    );
    final songs = _maps(_asMap(search?['result'])?['songs']);
    final song = songs.firstWhere((song) {
      final artists = _maps(
        song['artists'],
      ).map((artist) => artist['name']?.toString() ?? '').join(' ');
      return songMatches(
        wantedTitle: query.title,
        wantedArtist: query.artist,
        wantedDuration: query.durationSeconds,
        foundTitle: song['name']?.toString() ?? '',
        foundArtist: artists,
        foundDuration: null,
      );
    }, orElse: () => <String, dynamic>{});
    final songId = song['id'];
    if (songId == null) return null;
    final lyrics = _asMap(
      await _get.json(
        Uri.parse(
          '$_paxBase/netease/lyrics',
        ).replace(queryParameters: {'id': '$songId'}),
      ),
    );
    final lrc = _asMap(lyrics?['lrc'])?['lyric']?.toString() ?? '';
    return _candidate(
      id,
      () {
        if (lrc.trim().isEmpty) throw const LyricsFormatException('empty');
        return lrc.trim();
      },
      title: song['name']?.toString(),
      artist: _maps(
        song['artists'],
      ).map((artist) => artist['name']?.toString() ?? '').join(' '),
    );
  }
}

/// QQ Music: the song is checked against its length before the lyrics are
/// read. The lyric body is base64 LRC.
class QqMusicLyricsProvider implements OnlineLyricsProvider {
  QqMusicLyricsProvider(this._get);
  final LyricsHttpGet _get;

  static const _headers = {'Referer': 'https://y.qq.com/'};

  @override
  String get id => 'qqmusic';

  @override
  Future<OnlineLyricsCandidate?> find(OnlineLyricsQuery query) async {
    final search = _asMap(
      await _get.json(
        Uri.parse(
          'https://c.y.qq.com/splcloud/fcgi-bin/smartbox_new.fcg',
        ).replace(queryParameters: {'format': 'json', 'key': _paxQuery(query)}),
        extra: _headers,
      ),
    );
    final items = _maps(_asMap(_asMap(search?['data'])?['song'])?['itemlist']);
    final matches = items.where((song) {
      final mid = song['mid']?.toString() ?? '';
      final singer = (song['singer']?.toString() ?? '').replaceAll('/', ', ');
      return mid.isNotEmpty &&
          songMatches(
            wantedTitle: query.title,
            wantedArtist: query.artist,
            wantedDuration: null,
            foundTitle: song['name']?.toString() ?? '',
            foundArtist: singer,
            foundDuration: null,
          );
    });
    for (final song in matches.take(3)) {
      final duration = await _duration(song['mid'].toString());
      if (duration != null &&
          !durationsMatch(query.durationSeconds, duration)) {
        continue;
      }
      return _lyrics(song, query);
    }
    return null;
  }

  Future<double?> _duration(String mid) async {
    final detail = _asMap(
      await _get.json(
        Uri.parse(
          'https://c.y.qq.com/v8/fcg-bin/fcg_play_single_song.fcg',
        ).replace(queryParameters: {'format': 'json', 'songmid': mid}),
        extra: _headers,
      ),
    );
    final data = _maps(detail?['data']).toList();
    final seconds = data.isEmpty
        ? 0.0
        : (data.first['interval'] as num?)?.toDouble() ?? 0.0;
    return seconds > 0 ? seconds : null;
  }

  Future<OnlineLyricsCandidate?> _lyrics(
    Map<String, dynamic> song,
    OnlineLyricsQuery query,
  ) async {
    final response = _asMap(
      await _get.json(
        Uri.parse(
          'https://c.y.qq.com/lyric/fcgi-bin/fcg_query_lyric_new.fcg',
        ).replace(
          queryParameters: {
            'format': 'json',
            'inCharset': 'utf8',
            'outCharset': 'utf-8',
            'notice': '0',
            'platform': 'yqq.json',
            'needNewCode': '0',
            'songmid': song['mid'].toString(),
            'songid': '${song['id'] ?? ''}',
          },
        ),
        extra: _headers,
      ),
    );
    final raw = response?['lyric']?.toString() ?? '';
    if (response?['retcode'] != 0 && response?['code'] != 0) return null;
    return _candidate(
      id,
      () => decodeBase64Lyrics(raw),
      title: song['name']?.toString(),
      artist: (song['singer']?.toString() ?? '').replaceAll('/', ', '),
    );
  }
}

/// Kugou: search by "artist - title" with the length in milliseconds, then
/// download the LRC by candidate id and access key.
class KugouLyricsProvider implements OnlineLyricsProvider {
  KugouLyricsProvider(this._get);
  final LyricsHttpGet _get;

  @override
  String get id => 'kugou';

  @override
  Future<OnlineLyricsCandidate?> find(OnlineLyricsQuery query) async {
    final search = _asMap(
      await _get.json(
        Uri.parse('https://lyrics.kugou.com/search').replace(
          queryParameters: {
            'ver': '1',
            'man': 'yes',
            'client': 'pc',
            'keyword': '${query.artist} - ${query.title}'.trim(),
            'duration': ((query.durationSeconds ?? 0) * 1000)
                .round()
                .toString(),
            'hash': '',
          },
        ),
      ),
    );
    final song = _maps(search?['candidates']).firstWhere(
      (song) =>
          songMatches(
            wantedTitle: query.title,
            wantedArtist: query.artist,
            wantedDuration: query.durationSeconds,
            foundTitle: song['song']?.toString() ?? '',
            foundArtist: song['singer']?.toString() ?? '',
            foundDuration: ((song['duration'] as num?)?.toDouble() ?? 0) / 1000,
          ) &&
          (song['id']?.toString() ?? '').isNotEmpty &&
          (song['accesskey']?.toString() ?? '').isNotEmpty,
      orElse: () => <String, dynamic>{},
    );
    if (song.isEmpty) return null;
    final download = _asMap(
      await _get.json(
        Uri.parse('https://lyrics.kugou.com/download').replace(
          queryParameters: {
            'ver': '1',
            'client': 'pc',
            'id': song['id'].toString(),
            'accesskey': song['accesskey'].toString(),
            'fmt': 'lrc',
            'charset': 'utf8',
          },
        ),
      ),
    );
    if (download == null) return null;
    final content = download['content']?.toString() ?? '';
    if (content.isEmpty) return null;
    return _candidate(
      id,
      () => decodeBase64Lyrics(content),
      title: song['song']?.toString(),
      artist: song['singer']?.toString(),
      duration: ((song['duration'] as num?)?.toDouble() ?? 0) / 1000,
    );
  }
}

// ---------------------------------------------------------------------------
// Plain-text sources. Their results are shown in the plain-text group.
// ---------------------------------------------------------------------------

/// Genius: the song page's lyric containers, read as plain text.
class GeniusLyricsProvider implements OnlineLyricsProvider {
  GeniusLyricsProvider(this._get);
  final LyricsHttpGet _get;

  static const _pageHeaders = {
    'Accept': 'text/html,application/xhtml+xml',
    'Accept-Language': 'en-US,en;q=0.9',
  };

  @override
  String get id => 'genius';

  @override
  Future<OnlineLyricsCandidate?> find(OnlineLyricsQuery query) async {
    final search = _asMap(
      await _get.json(
        Uri.parse(
          'https://genius.com/api/search/multi',
        ).replace(queryParameters: {'q': _paxQuery(query), 'per_page': '5'}),
      ),
    );
    final sections = _maps(_asMap(search?['response'])?['sections']);
    final hit = sections
        .expand((section) => _maps(section['hits']))
        .where((hit) => hit['type'] == 'song')
        .map((hit) => _asMap(hit['result']))
        .whereType<Map<String, dynamic>>()
        .firstWhere((song) {
          final primary = song['primary_artist_names']?.toString().trim() ?? '';
          final artist = primary.isNotEmpty
              ? primary
              : song['artist_names']?.toString() ?? '';
          return (song['url']?.toString() ?? '').isNotEmpty &&
              songMatches(
                wantedTitle: query.title,
                wantedArtist: query.artist,
                wantedDuration: null,
                foundTitle: song['title']?.toString() ?? '',
                foundArtist: artist,
                foundDuration: null,
              );
        }, orElse: () => <String, dynamic>{});
    final url = hit['url']?.toString() ?? '';
    if (url.isEmpty) return null;
    final page = await _get.call(Uri.parse(url), extra: _pageHeaders);
    if (page == null) return null;
    return _candidate(
      id,
      () => extractGeniusLyrics(
        utf8.decode(page.bodyBytes, allowMalformed: true),
      ),
      title: hit['title']?.toString(),
      artist:
          hit['primary_artist_names']?.toString() ??
          hit['artist_names']?.toString(),
    );
  }
}

/// Every built-in source. The search asks all of them once, at the same time.
List<OnlineLyricsProvider> onlineLyricsProviders(http.Client client) {
  final get = LyricsHttpGet(
    client,
    headers: const {'User-Agent': 'Sistrum lyrics'},
  );
  return [
    // Word-timed sources first; the results are grouped by timing anyway.
    AppleLyricsProvider(get, zarz: false),
    AppleLyricsProvider(get, zarz: true),
    MusixmatchLyricsProvider(get),
    LyricsPlusProvider(get),
    BetterLyricsProvider(get),
    LrcRedLyricsProvider(get),
    SpotifyLyricsProvider(get),
    DeezerLyricsProvider(get),
    YouTubeLyricsProvider(get),
    // Line-timed sources, then plain-text sources.
    LrcLibLyricsProvider(client: client),
    NeteaseLyricsProvider(get),
    QqMusicLyricsProvider(get),
    KugouLyricsProvider(get),
    GeniusLyricsProvider(get),
  ];
}
