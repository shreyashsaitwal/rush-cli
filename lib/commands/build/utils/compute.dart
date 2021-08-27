import 'dart:async';
import 'dart:developer';
import 'dart:isolate';

import 'package:meta/meta.dart';

// Note:
// This file is picked from the Flutter framework with some minor changes to make
// it work with Rush.

/// Spawn an isolate, run `callback` on that isolate, passing it `message`, and
/// (eventually) return the value returned by `callback`.
///
/// This is useful for operations that take longer than a few milliseconds, and
/// which would therefore risk skipping frames. For tasks that will only take a
/// few milliseconds, consider [SchedulerBinding.scheduleTask] instead.
///
/// {@template flutter.foundation.compute.types}
/// `Q` is the type of the message that kicks off the computation.
///
/// `R` is the type of the value returned.
/// {@endtemplate}
///
/// The `callback` argument must be a top-level function, not a closure or an
/// instance or static method of a class.
///
/// {@template flutter.foundation.compute.limitations}
/// There are limitations on the values that can be sent and received to and
/// from isolates. These limitations constrain the values of `Q` and `R` that
/// are possible. See the discussion at [SendPort.send].
/// {@endtemplate}
///
/// The `debugLabel` argument can be specified to provide a name to add to the
/// [Timeline]. This is useful when profiling an application.
Future<R> compute<Q, R>(ComputeCallback<Q, R> callback, Q message,
    {String? debugLabel}) async {
  final flow = Flow.begin();
  Timeline.startSync('$debugLabel: start', flow: flow);

  final resultPort = ReceivePort();
  final exitPort = ReceivePort();
  final errorPort = ReceivePort();

  Timeline.finishSync();
  final isolate = await Isolate.spawn<_IsolateConfiguration<Q, FutureOr<R>>>(
    _spawn,
    _IsolateConfiguration<Q, FutureOr<R>>(
      callback,
      message,
      resultPort.sendPort,
      'compute',
      flow.id,
    ),
    errorsAreFatal: true,
    onExit: exitPort.sendPort,
    onError: errorPort.sendPort,
  );

  final result = Completer<R>();
  errorPort.listen((dynamic errorData) {
    assert(errorData is List<dynamic>);
    assert(errorData.length == 2);
    final exception = Exception(errorData[0]);
    final stack = StackTrace.fromString(errorData[1] as String);
    if (result.isCompleted) {
      Zone.current.handleUncaughtError(exception, stack);
    } else {
      result.completeError(exception, stack);
    }
  });

  exitPort.listen((dynamic exitData) {
    if (!result.isCompleted) {
      result
          .completeError(Exception('Isolate exited without result or error.'));
    }
  });

  resultPort.listen((dynamic resultData) {
    assert(resultData == null || resultData is R);
    if (!result.isCompleted) result.complete(resultData as R);
  });

  await result.future;
  Timeline.startSync('$debugLabel: end', flow: Flow.end(flow.id));
  resultPort.close();
  errorPort.close();
  isolate.kill();
  Timeline.finishSync();
  return result.future;
}

Future<void> _spawn<Q, R>(
    _IsolateConfiguration<Q, FutureOr<R>> configuration) async {
  final result = await Timeline.timeSync(
    configuration.debugLabel,
    () async {
      final applicationResult = await configuration.apply();
      return await applicationResult;
    },
    flow: Flow.step(configuration.flowId),
  );

  Timeline.timeSync(
    '${configuration.debugLabel}: returning result',
    () {
      configuration.resultPort.send(result);
    },
    flow: Flow.step(configuration.flowId),
  );
}

typedef ComputeCallback<Q, R> = FutureOr<R> Function(Q message);

@immutable
class _IsolateConfiguration<Q, R> {
  final ComputeCallback<Q, R> callback;
  final Q message;
  final SendPort resultPort;
  final String debugLabel;
  final int flowId;
  const _IsolateConfiguration(
    this.callback,
    this.message,
    this.resultPort,
    this.debugLabel,
    this.flowId,
  );

  FutureOr<R> apply() => callback(message);
}
