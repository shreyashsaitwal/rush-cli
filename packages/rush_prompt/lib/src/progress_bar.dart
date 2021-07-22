import 'package:dart_console/dart_console.dart';

class ProgressBar {
  final int _totalLen;

  ProgressBar(this._totalLen) {
    _render(0, _totalLen);
  }

  int _currLen = 0;

  void incr() {
    _currLen++;
    _render(_currLen, _totalLen);
  }

  void _render(int prog, int total) {
    final console = Console();

    console
      ..cursorUp()
      ..eraseLine();

    // Total length of the bar (45% of terminal window's)
    final barLen = console.windowWidth * 0.45;

    final progPerc = prog / total;
    final progLen = barLen * progPerc;

    console
      ..write(' ' * 5)
      ..setBackgroundColor(ConsoleColor.blue)
      ..write(' ' * progLen.toInt())
      ..setBackgroundColor(ConsoleColor.brightBlack)
      ..write(' ' * (barLen.toInt() - progLen.toInt()))
      ..resetColorAttributes()
      ..writeLine(' (${(progPerc * 100).toInt()}% done)');
  }
}
