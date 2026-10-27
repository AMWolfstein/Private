import 'dart:async';

/// Observes caller scheduling order, not how long an operation takes.
///
/// Attach completion first: an already completed future must not pass merely
/// because its completion notification itself uses a microtask. Worker replies
/// arrive as isolate/platform events, after this caller microtask. This proves a
/// caller opportunity before completion, not responsiveness throughout the job.
Future<({T value, bool yieldedBeforeCompletion})> probeCallerYield<T>(
  FutureOr<T> Function() operation,
) async {
  final pending = operation();
  if (pending is! Future<T>) {
    return (value: pending, yieldedBeforeCompletion: false);
  }
  var completed = false;
  final observed = pending.then(
    (value) {
      completed = true;
      return value;
    },
    onError: (Object error, StackTrace stack) {
      completed = true;
      Error.throwWithStackTrace(error, stack);
    },
  );
  final probe = Completer<bool>();
  scheduleMicrotask(() => probe.complete(!completed));
  final value = await observed;
  return (value: value, yieldedBeforeCompletion: await probe.future);
}
