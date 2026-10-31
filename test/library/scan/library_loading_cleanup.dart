part of 'library_loading_test.dart';

void _registerLibraryLoadingCleanup() {
  test(
    'physical deletion removes collection references for every indexed alias',
    () async {
      container.read(localLibraryProvider);
      await _waitFor(() => !container.read(localLibraryProvider).isLoading);
      await _library.removePhysicalFiles(['/music/deleted.flac']);
      expect(_collections.removedIds, ['deleted', 'alias']);
      expect(_database.removedIds, ['deleted', 'alias']);
    },
  );

  test(
    'collection cleanup failure retains row identity for deletion retry',
    () async {
      container.read(localLibraryProvider);
      await _waitFor(() => !container.read(localLibraryProvider).isLoading);
      _collections.failRemoval = true;
      await expectLater(_library.removeItems(['deleted']), throwsStateError);
      expect(_database.removedIds, isEmpty);
      _collections.failRemoval = false;
      await _library.removeItems(['deleted']);
      expect(_database.removedIds, ['deleted']);
    },
  );
}
