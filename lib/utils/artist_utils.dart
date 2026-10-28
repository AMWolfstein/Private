final RegExp _artistNameSplitPattern = RegExp(
  r'\s*(?:,|;|&|\bx\b)\s*|\s+\b(?:feat(?:uring|ured|ure)?|ft|with)\.?(?=\s|$)\s*',
  caseSensitive: false,
);

List<String> splitArtistNames(String rawArtists, {int? creditedArtistCount}) {
  final raw = rawArtists.trim();
  if (raw.isEmpty) return const [];

  final names = raw
      .split(_artistNameSplitPattern)
      .map((part) => part.trim())
      .where((part) => part.isNotEmpty)
      .toList(growable: false);
  // "and" can be part of a band's name. Only treat it as a separator when
  // the provider's separate artist IDs confirm that many credited artists.
  if (creditedArtistCount != null && creditedArtistCount > names.length) {
    final expanded = names
        .expand(
          (name) => name.split(RegExp(r'\s+and\s+', caseSensitive: false)),
        )
        .map((name) => name.trim())
        .where((name) => name.isNotEmpty)
        .toList(growable: false);
    if (expanded.length == creditedArtistCount) return expanded;
  }
  return names;
}
