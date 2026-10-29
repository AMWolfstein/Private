import 'package:sistrum/services/library/library_database_models.dart';

/// Source management that the folder picker needs from the local library. The
/// library notifier implements it; the service never imports the provider.
abstract interface class LibrarySourceSink {
  Future<LocalLibrarySource> addSource({
    required String path,
    required String displayName,
    String? volumeId,
    bool isRemovable = false,
  });

  Future<void> startSourceScan(String sourceId, {bool forceFullScan = false});
}

/// Row and file removal that the deletion service needs from the local library.
abstract interface class LibraryRemovalSink {
  Future<void> removePhysicalFiles(Iterable<String> filePaths);

  Future<void> removeItems(Iterable<String> ids);
}
