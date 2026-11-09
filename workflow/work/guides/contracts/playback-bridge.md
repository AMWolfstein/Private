# Playback bridge contract checklist

Applies to a Dart→Kotlin playback MethodChannel and Kotlin→Dart EventChannel. Namespace, signatures and serialization are chosen in the bridge's design.

Commands: setQueue/enqueue/move/remove; play/pause/seek/skipToNext/skipToPrevious/skipToIndex/stop; shuffle/repeat/sleep timer; settings; restore/retry. Events: queue/current item, state, position/duration, error including decoder provider, AutoMix/output/route and EQ/limiter status.

Before implementing a command, specify and test:
- Field names, required/optional values, integer widths, units, bounds, URI/CUE interpretation and compatibility rules.
- Typed application results; distinguish not found, unsupported, permission failure, cancellation and operation failure. Null must not conceal failure.
- Ordering, command acceptance versus completion, concurrent requests and stale event rejection.
- Authoritative snapshot on reconnect; events after disposal/recreation; listener attach/detach; service lifetime without Flutter.
- Dispatcher and blocking work; bounded payloads and event frequency; buffers/temporary files and ownership.
- Cancellation before dispatch/during workflow/work/after commit; exactly one terminal completion for each accepted request.

Shared fixture cases run against both Dart serialization and Kotlin parsing/dispatch. Include malformed payloads, missing plugins/service, out-of-order callbacks, rapid play/pause/seek, failed prepare and reconnect. Preserve retry selection and same-ID metadata updates without resetting playback.

No automatic MethodChannel→FFI migration. A transport change needs measured evidence and a contract review.
