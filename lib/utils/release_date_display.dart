import 'package:intl/intl.dart';

final _releaseYear = RegExp(r'(\d{4})');
final _releaseDate = RegExp(
  r'^(\d{4})(?:[-/](\d{1,2})(?:[-/](\d{1,2}))?|(\d{2})(\d{2})?)?(?:[T ].*)?$',
);
final _releaseFormats = <(String, int), DateFormat>{};

/// Retain only the year from common local release-tag forms, including YYYYMMDD.
String? releaseTagYear(String? value) =>
    value == null ? null : _releaseYear.firstMatch(value)?.group(1);

/// Format only validated local tags, preserving their year/month/day precision.
String? formatReleaseTag(String? value, String locale) {
  if (value == null || value.length > 64) return null;
  final match = _releaseDate.firstMatch(value.trim());
  if (match == null) return null;
  final year = int.parse(match[1]!);
  final monthTag = match[2] ?? match[4];
  final dayTag = match[3] ?? match[5];
  final month = int.tryParse(monthTag ?? '1')!;
  final day = int.tryParse(dayTag ?? '1')!;
  final date = DateTime(year, month, day);
  if (year < 1 || date.year != year || date.month != month || date.day != day)
    return null;
  final precision = dayTag != null
      ? 3
      : monthTag != null
      ? 2
      : 1;
  try {
    // Bound the cache even if imported locale strings are untrusted.
    if (_releaseFormats.length >= 64) _releaseFormats.clear();
    final format = _releaseFormats.putIfAbsent(
      (locale, precision),
      () => switch (precision) {
        3 => DateFormat.yMMMd(locale),
        2 => DateFormat.yMMMM(locale),
        _ => DateFormat.y(locale),
      },
    );
    return format.format(date);
  } catch (_) {
    return year.toString();
  }
}
