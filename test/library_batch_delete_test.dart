import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:sistrum/widgets/app_alert_dialog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/l10n/app_localizations.dart';
import 'package:sistrum/services/deleted_library_files.dart';
import 'package:sistrum/services/library/library_cleanup.dart';
import 'package:sistrum/widgets/confirm_and_delete_tracks.dart';
import 'package:sqflite/sqflite.dart';

class _DeleteDatabase implements Database, Transaction {
  final rows = <String>{};
  final pathKeys = <String>{};
  final chunks = <List<Object?>>[];
  int transactions = 0;
  bool failRows = false;

  @override
  Future<T> transaction<T>(
    Future<T> Function(Transaction txn) action, {
    bool? exclusive,
  }) async {
    transactions++;
    final previousRows = Set<String>.of(rows);
    final previousKeys = Set<String>.of(pathKeys);
    try {
      return await action(this);
    } catch (_) {
      rows
        ..clear()
        ..addAll(previousRows);
      pathKeys
        ..clear()
        ..addAll(previousKeys);
      rethrow;
    }
  }

  @override
  Future<int> delete(
    String table, {
    String? where,
    List<Object?>? whereArgs,
  }) async {
    expect(whereArgs!.length, lessThanOrEqualTo(500));
    expect('?'.allMatches(where!).length, whereArgs.length);
    expect(table, isIn(['library_path_keys', 'library']));
    if (table == 'library_path_keys') {
      expect(where, startsWith('item_id IN ('));
      chunks.add(List.of(whereArgs));
      pathKeys.removeAll(whereArgs);
    } else {
      expect(where, startsWith('id IN ('));
      expect(whereArgs, chunks.last);
      if (failRows) throw StateError('write failed');
      rows.removeAll(whereArgs);
    }
    return whereArgs.length;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('large selection deletes paired rows in bounded chunks once', () async {
    final ids = List.generate(1205, (index) => 'track-$index');
    final db = _DeleteDatabase()
      ..rows.addAll([...ids, 'retained'])
      ..pathKeys.addAll([...ids, 'retained']);
    await deleteLibraryItemsByIds(db, [...ids, ...ids.take(10)]);
    expect(db.transactions, 1);
    expect(db.chunks.map((chunk) => chunk.length), [500, 500, 205]);
    expect(db.chunks.expand((chunk) => chunk), ids);
    expect(db.rows, {'retained'});
    expect(db.pathKeys, {'retained'});
  });

  test('empty selection skips storage; failure keeps rows and keys', () async {
    final db = _DeleteDatabase()
      ..rows.add('retained')
      ..pathKeys.add('retained');
    await deleteLibraryItemsByIds(db, []);
    expect(db.transactions, 0);
    db.failRows = true;
    await expectLater(
      deleteLibraryItemsByIds(db, ['retained']),
      throwsStateError,
    );
    expect(db.rows, {'retained'});
    expect(db.pathKeys, {'retained'});
  });

  for (final mode in ['partial', 'cancel', 'throw', 'none', 'leave']) {
    testWidgets('batch confirmation runs one deletion operation: $mode', (
      tester,
    ) async {
      final events = <String>[];
      final commit = Completer<void>();
      DeletedLibraryTracks? result;
      Object? failure;
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () async {
                    try {
                      result = await confirmAndDeleteTracks(
                        context: context,
                        ids: ['first', 'failed', 'last'],
                        deleteItems: (ids) async {
                          events.add('delete:${ids.join(',')}');
                          if (mode == 'none') {
                            return DeletedLibraryTracks(
                              deletedIds: const [],
                              requested: ids.length,
                            );
                          }
                          await commit.future;
                          if (mode == 'throw') {
                            throw StateError('file delete failed');
                          }
                          final deletedIds = mode == 'partial'
                              ? const ['first', 'last']
                              : ids;
                          events.add('deleted:${deletedIds.join(',')}');
                          return DeletedLibraryTracks(
                            deletedIds: deletedIds,
                            requested: ids.length,
                          );
                        },
                        onExitSelectionMode: () => events.add('exit'),
                      );
                    } catch (error) {
                      failure = error;
                    }
                  },
                  child: const Text('Start'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Start'));
      await tester.pumpAndSettle();
      if (mode == 'cancel') {
        await tester.tap(find.widgetWithText(AppDialogAction, 'Cancel'));
      } else {
        await tester.tap(find.widgetWithText(AppDialogAction, 'Delete'));
      }
      await tester.pumpAndSettle();
      if (mode == 'cancel') {
        expect(events, isEmpty);
      } else {
        // One operation receives every confirmed ID; a synchronous result can
        // already have shown its snackbar by now.
        expect(events.first, 'delete:first,failed,last');
      }
      if (mode == 'leave') await tester.pumpWidget(const SizedBox());
      commit.complete();
      await tester.pumpAndSettle();
      if (mode == 'throw') {
        expect(failure, isStateError);
        expect(events, isNot(contains('exit')));
      } else {
        expect(failure, isNull);
        expect(result?.deletedCount, switch (mode) {
          'cancel' => null,
          'none' => 0,
          'partial' => 2,
          _ => 3,
        });
        if (mode == 'cancel') {
          expect(events, isEmpty);
        } else if (mode == 'leave') {
          expect(events, isNot(contains('exit')));
        } else {
          expect(events.last, 'exit');
          final message = tester
              .widget<Text>(
                find
                    .descendant(
                      of: find.byType(SnackBar),
                      matching: find.byType(Text),
                    )
                    .first,
              )
              .data!;
          expect(
            message,
            contains(
              mode == 'none'
                  ? 'Could not delete 3 tracks'
                  : 'Could not delete 1 track',
            ),
          );
          expect(message, isNot(contains('Deleted 0')));
        }
      }
      expect(tester.takeException(), isNull);
    });
  }
}
