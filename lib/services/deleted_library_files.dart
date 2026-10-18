import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spotiflac_android/providers/local_library_provider.dart';

/// Call only after deletion succeeds. Scanned rows can share a physical file,
/// so every index must be cleared together. Capture the app container before
/// I/O so leaving the screen cannot prevent cleanup after a slow deletion.
Future<void> removeDeletedLibraryFileEntries(
  ProviderContainer container,
  Iterable<String> filePaths,
) async {
  final paths = filePaths.toSet();
  if (paths.isEmpty) return;
  await container
      .read(localLibraryProvider.notifier)
      .removePhysicalFiles(paths);
}
