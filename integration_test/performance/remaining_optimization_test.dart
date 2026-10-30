import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../collections/library_collections_workers_test.dart' as collections;
import '../native/native_backup_archive_test.dart' as archive;
import '../native/native_cache_maintenance_test.dart' as cache;
import '../native/native_collection_restore_test.dart' as restore;
import '../native/native_library_staging_test.dart' as library_staging;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  group('collection restore', restore.main);
  group('library staging', library_staging.main);
  group('cache maintenance', cache.main);
  group('collection workers', collections.main);
  group('backup archive', archive.main);
}
