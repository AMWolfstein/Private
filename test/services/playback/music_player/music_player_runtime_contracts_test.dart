import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/services/playback/automix/automix_status.dart';
import 'package:sistrum/services/playback/core/playback_handler.dart';
import 'package:sistrum/services/playback/music_player/music_player_runtime.dart';

import '../../../support/music_player_harness.dart';

void main() {
  group('restoreSession retry', () {
    test('a failed restore is retried by the next call', () async {
      var attempts = 0;
      final runtime = musicPlayerRuntimeFor(
        restoreSession: (_) async {
          attempts++;
          return attempts == 1
              ? PlaybackRestoreOutcome.failed
              : PlaybackRestoreOutcome.restored;
        },
      );

      expect(await runtime.restoreSession(), PlaybackRestoreOutcome.failed);
      expect(await runtime.restoreSession(), PlaybackRestoreOutcome.restored);
      expect(attempts, 2);
    });

    test('a finished restore is not repeated', () async {
      var attempts = 0;
      final runtime = musicPlayerRuntimeFor(
        restoreSession: (_) async {
          attempts++;
          return PlaybackRestoreOutcome.restored;
        },
      );

      await runtime.restoreSession();
      await runtime.restoreSession();
      expect(attempts, 1);
    });

    test('concurrent calls share one attempt while it is pending', () async {
      var attempts = 0;
      final gate = Completer<PlaybackRestoreOutcome>();
      final runtime = musicPlayerRuntimeFor(
        restoreSession: (_) {
          attempts++;
          return gate.future;
        },
      );

      final first = runtime.restoreSession();
      final second = runtime.restoreSession();
      gate.complete(PlaybackRestoreOutcome.failed);

      expect(await first, PlaybackRestoreOutcome.failed);
      expect(await second, PlaybackRestoreOutcome.failed);
      expect(attempts, 1);
    });

    test('an empty saved session is final, not a failure', () async {
      var attempts = 0;
      final runtime = musicPlayerRuntimeFor(
        restoreSession: (_) async {
          attempts++;
          return PlaybackRestoreOutcome.nothingSaved;
        },
      );

      expect(
        await runtime.restoreSession(),
        PlaybackRestoreOutcome.nothingSaved,
      );
      await runtime.restoreSession();
      expect(attempts, 1);
    });
  });

  group('player widget binding', () {
    test(
      'a scoped runtime without the binding leaves the widget alone',
      () async {
        final bound = <PlaybackHandler>[];
        final scoped = musicPlayerRuntimeFor(
          isAndroid: true,
          bindPlayerWidget: null,
        );

        final handler = await scoped.initialize();

        expect(bound, isEmpty);
        expect(handler, isNotNull);
      },
    );

    test('each Android runtime binds only its own handler', () async {
      final first = <PlaybackHandler>[];
      final second = <PlaybackHandler>[];
      final a = musicPlayerRuntimeFor(
        isAndroid: true,
        bindPlayerWidget: first.add,
      );
      final b = musicPlayerRuntimeFor(
        isAndroid: true,
        bindPlayerWidget: second.add,
      );

      final handlerA = await a.initialize();
      final handlerB = await b.initialize();

      expect(first, [handlerA]);
      expect(second, [handlerB]);
    });

    test('a non-Android runtime never binds', () async {
      final bound = <PlaybackHandler>[];
      final runtime = musicPlayerRuntimeFor(
        isAndroid: false,
        bindPlayerWidget: bound.add,
      );

      await runtime.initialize();

      expect(bound, isEmpty);
    });
  });

  group('AutoMix status ownership', () {
    test('disposing a live handler resets only its own runtime sink', () async {
      final sink = ValueNotifier<AutoMixStatus>(AutoMixStatus.mixing);
      final runtime = musicPlayerRuntimeFor(autoMixStatus: sink);
      final handler = await runtime.initialize();

      await handler.dispose();

      expect(sink.value, AutoMixStatus.idle);
    });

    test(
      'a scoped runtime without a sink cannot touch the process badge',
      () async {
        final processBadge = ValueNotifier<AutoMixStatus>(AutoMixStatus.mixing);
        addTearDown(processBadge.dispose);
        final scoped = musicPlayerRuntimeFor();
        final handler = await scoped.initialize();

        await handler.dispose();

        expect(processBadge.value, AutoMixStatus.mixing);
      },
    );
  });
}
