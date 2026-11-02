import 'package:flutter_riverpod/flutter_riverpod.dart';

/// One alphabetical direction shared by every Library route.
final librarySortProvider = NotifierProvider<LibrarySortNotifier, String>(
  LibrarySortNotifier.new,
);

class LibrarySortNotifier extends Notifier<String> {
  @override
  String build() => 'a-z';

  void select(String value) {
    if (value != 'a-z' && value != 'z-a') {
      throw ArgumentError.value(value, 'value', 'Expected a-z or z-a');
    }
    state = value;
  }
}
