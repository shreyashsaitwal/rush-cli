import 'dart:async';
import 'dart:developer';
import 'dart:isolate';

import 'package:meta/meta.dart';

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
