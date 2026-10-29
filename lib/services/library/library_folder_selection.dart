import 'package:file_picker/file_picker.dart';
import 'package:sistrum/services/library/library_mutation_ports.dart';
import 'package:sistrum/services/platform_bridge.dart';

/// Decodes a SAF tree URI into a readable folder path for display.
String libraryFolderDisplayPath(String path) {
  if (!path.startsWith('content://')) return path;
  try {
    final uri = Uri.parse(path);
    // `pathSegments` already percent-decodes; a second pass would rewrite a
    // literal `%XX` in the folder name.
    final decoded = uri.pathSegments.last;
    if (decoded.startsWith('primary:')) {
      return '/storage/emulated/0/${decoded.substring('primary:'.length)}';
    }
    return decoded;
  } catch (_) {
    return path;
  }
}

/// Adds the folder the user picks to the local library and starts its first
/// scan. Android 10+ ([androidSdkVersion] 29 or later) uses the scoped
/// storage-access-framework tree picker, so the local library never needs the
/// all-files permission; older Android and other platforms use the folder
/// picker after the caller has the storage permission.
///
/// Returns true when a library source was added.
Future<bool> selectLibraryFolder(
  LibrarySourceSink library, {
  required int androidSdkVersion,
  void Function(String message)? onFailure,
}) async {
  if (androidSdkVersion >= 29) {
    final result = await PlatformBridge.pickSafTree(onFailure: onFailure);
    if (result == null) return false;
    final treeUri = result['tree_uri'] as String? ?? '';
    if (treeUri.isEmpty) return false;
    final source = await library.addSource(
      path: treeUri,
      displayName:
          result['display_name'] as String? ??
          libraryFolderDisplayPath(treeUri),
      volumeId: result['volume_id'] as String?,
      isRemovable: result['is_removable'] == true,
    );
    await library.startSourceScan(source.id);
    return true;
  }

  final path = await FilePicker.getDirectoryPath();
  if (path == null) return false;
  final source = await library.addSource(path: path, displayName: path);
  await library.startSourceScan(source.id);
  return true;
}
