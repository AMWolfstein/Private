import 'package:flutter/widgets.dart';

final _letterPattern = RegExp(r'[\p{L}]', unicode: true);

String librarySectionInitial(String value) {
  final text = value.trim();
  if (text.isEmpty) return '#';
  final first = text.characters.first;
  return _letterPattern.hasMatch(first) ? first.toUpperCase() : '#';
}
