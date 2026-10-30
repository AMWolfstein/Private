import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sistrum/services/library/database/library_database.dart';

/// The local-library database that providers read. Tests override this
/// provider instead of replacing the process-wide singleton.
final libraryDatabaseProvider = Provider<LibraryDatabase>(
  (ref) => LibraryDatabase.instance,
);
