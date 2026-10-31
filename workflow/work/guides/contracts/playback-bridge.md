# Playback bridge contract checklist

Target from migration section 6.1: a Dart→Kotlin playback MethodChannel and Kotlin→Dart EventChannel. Final namespace, signatures and serialization are chosen in the first bridge design, not invented by this starter.

Commands: setQueue/enqueue/move/remove; play/pause/seek/skipToNext/skipToPrevious/skipToIndex/stop; shuffle/repeat/sleep timer; settings; restore/retry. Events: queue/current item, state, position/duration, error including decoder provider, AutoMix/output/route and EQ/limiter status.

Before implementing a command, specify and test:
- Field names, required/optional values, integer widths, units, bounds, URI/CUE interpretation and compatibility rules.
- Typed application results; distinguish not found, unsupported, permission failure, cancellation and operation failure. Null must not conceal failure.
- Ordering, command acceptance versus completion, concurrent requests and stale event rejection.
- Authoritative snapshot on reconnect; events after disposal/recreation; listener attach/detach; service lifetime without Flutter.
- Dispatcher and blocking work; bounded payloads and event frequency; buffers/temporary files and ownership.
- Cancellation before dispatch/during work/after commit; exactly one terminal completion for each accepted request.

Shared fixture cases run against both Dart serialization and Kotlin parsing/dispatch. Include malformed payloads, missing plugins/service, out-of-order callbacks, rapid play/pause/seek, failed prepare and reconnect. Preserve retry selection and same-ID metadata updates without resetting playback.

No automatic MethodChannel→FFI migration. A transport change needs measured evidence and a contract review. Direct USB libusb and AAudio are intentionally retired; Android 14+ bit-perfect/DoP remains a distinct output path with DSP/normalization/AutoMix bypass behavior.
