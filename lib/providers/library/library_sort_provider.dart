import 'package:flutter_riverpod/flutter_riverpod.dart';

const librarySortModes = [
  'a-z',
  'z-a',
  'size-desc',
  'size-asc',
  'release-newest',
  'release-oldest',
];

/// One order shared by Library routes, with alphabetical order as the default.
final librarySortProvider = NotifierProvider<LibrarySortNotifier, String>(
  LibrarySortNotifier.new,
);

class LibrarySortNotifier extends Notifier<String> {
  @override
  String build() => 'a-z';

  void select(String value) {
    if (!librarySortModes.contains(value)) {
      throw ArgumentError.value(value, 'value', 'Unknown Library order');
    }
    state = value;
  }
}
