import 'package:process_runner/process_runner.dart';

class ProcessStreamer {
  /// Starts a process from given [args] and returns a stream of events
  /// emitted by that process.
  static Stream<ProcessRunnerResult> stream(List<String> args) async* {
    final process =
        ProcessRunner().runProcess(args).asStream().asBroadcastStream();

    try {
      await for (final data in process) {
        yield data;
      }
    } catch (e) {
      rethrow;
    }
  }
}
