final _releaseYear = RegExp(r'(\d{4})');

/// Retain only the year from common local release-tag forms, including YYYYMMDD.
String? releaseTagYear(String? value) =>
    value == null ? null : _releaseYear.firstMatch(value)?.group(1);
