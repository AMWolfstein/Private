/// Song matching shared by every online lyrics source. A result is accepted
/// only when its title and artist agree with the song, and when its duration
/// agrees too whenever both sides know it.
library;

const maxDurationDifferenceSeconds = 3.0;

final _bracketed = RegExp(r'[\(\[][^\)\]]*[\)\]]');
final _nonWord = RegExp(r'[^\p{L}\p{N}]+', unicode: true);
final _versionSuffix = RegExp(r'\s[-–]\s.*$');

/// Lowercase title with brackets, a trailing " - version" suffix, punctuation
/// and spacing removed. "Yesterday - Remastered" becomes "yesterday".
String normalizeTitle(String value) => value
    .toLowerCase()
    .replaceAll(_versionSuffix, ' ')
    .replaceAll(_bracketed, ' ')
    .replaceAll(_nonWord, ' ')
    .trim();

/// Tokens used only to recognize a full artist credit in a video title.
Set<String> artistWords(String value) => value
    .toLowerCase()
    .replaceAll(_nonWord, ' ')
    .trim()
    .split(' ')
    .where(
      (word) =>
          word.isNotEmpty &&
          !const {
            'feat',
            'ft',
            'featuring',
            'with',
            'and',
            'x',
            'vs',
          }.contains(word),
    )
    .toSet();

/// Compares full normalized names, including explicitly separated featured
/// credits. Sharing a first name is never enough to identify an artist.
bool artistsMatch(String wanted, String found) {
  String normalized(String value) =>
      value.toLowerCase().replaceAll(_nonWord, ' ').trim();
  final a = normalized(wanted), b = normalized(found);
  if (a.isEmpty || b.isEmpty) return false;
  if (a == b) return true;
  final separator = RegExp(
    r'\s+(?:feat\.?|ft\.?|featuring|with|and|vs\.?|x)\s+|[;,]|\s+&\s+',
    caseSensitive: false,
  );
  Set<String> credits(String value) =>
      value.split(separator).map(normalized).where((s) => s.isNotEmpty).toSet();
  return credits(wanted).intersection(credits(found)).isNotEmpty;
}

bool durationsMatch(double? wanted, double? found) {
  if (wanted == null || found == null || wanted <= 0 || found <= 0) return true;
  return (wanted - found).abs() <= maxDurationDifferenceSeconds;
}

/// Parses "m:ss", "h:mm:ss" or a plain number of seconds. Null if unreadable.
double? parseClockSeconds(String? value) {
  final raw = value?.trim() ?? '';
  if (raw.isEmpty) return null;
  final parts = raw.split(':');
  if (parts.length > 3) return null;
  double total = 0;
  for (final part in parts) {
    final number = double.tryParse(part);
    if (number == null) return null;
    total = total * 60 + number;
  }
  return total;
}

/// Whether a source's title, artist and duration describe the wanted song.
bool songMatches({
  required String wantedTitle,
  required String wantedArtist,
  required double? wantedDuration,
  required String foundTitle,
  required String foundArtist,
  required double? foundDuration,
}) {
  if (normalizeTitle(wantedTitle) != normalizeTitle(foundTitle)) return false;
  if (!artistsMatch(wantedArtist, foundArtist)) return false;
  return durationsMatch(wantedDuration, foundDuration);
}
