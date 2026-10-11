import 'dart:io';

import 'package:interact/interact.dart';
import 'package:tint/tint.dart';

class Progress {
  Progress({required String running, required String done})
      : _done = done,
        _spinner = stdout.hasTerminal
            ? Spinner(
                icon: '\n✓ '.green(),
                rightPrompt: (isDone) => isDone ? done : running,
              ).interact()
            : null;

  final String _done;
  final SpinnerState? _spinner;

  void finish() {
    final spinner = _spinner;
    if (spinner != null) {
      spinner.done();
    } else {
      stdout.writeln('${'✓ '.green()}$_done');
    }
  }
}
