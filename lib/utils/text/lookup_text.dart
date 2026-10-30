/// Lookup keys compare trimmed, lowercased text; accents are kept as typed.
String normalizeLookupText(String? value) {
  return (value ?? '').trim().toLowerCase();
}
