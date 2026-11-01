import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sistrum/services/library/collections/library_preference_events.dart';

/// Scoped with the provider container, like the library state it describes.
final libraryPreferenceEventsProvider = Provider<LibraryPreferenceEvents>(
  (ref) => LibraryPreferenceEvents(),
);
