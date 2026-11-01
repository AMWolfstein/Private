import 'package:sistrum/core/models/track.dart';
import 'package:sistrum/utils/logging/logger.dart';

enum LibraryPreferenceKind { loved, playlisted }

/// Only committed user choices are published; loading/importing collections
/// does not manufacture feedback. Consumers own their subscription lifetime.
class LibraryPreferenceEvents {
  final _listeners = <Object, void Function(Track, LibraryPreferenceKind)>{};
  void Function() subscribe(
    void Function(Track, LibraryPreferenceKind) listener,
  ) {
    final token = Object();
    _listeners[token] = listener;
    return () => _listeners.remove(token);
  }

  void publish(Track track, LibraryPreferenceKind kind) {
    for (final entry in Map.of(_listeners).entries) {
      if (!_listeners.containsKey(entry.key)) continue;
      try {
        entry.value(track, kind);
      } catch (error) {
        AppLogger(
          'LibraryPreferenceEvents',
        ).w('Optional preference consumer failed: $error');
      }
    }
  }
}
