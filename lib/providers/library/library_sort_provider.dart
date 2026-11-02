import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A session-wide Library order. Null preserves each page's original default.
final librarySortProvider = NotifierProvider<LibrarySortNotifier, String?>(
  LibrarySortNotifier.new,
);

class LibrarySortNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String value) => state = value == 'original' ? null : value;
}
