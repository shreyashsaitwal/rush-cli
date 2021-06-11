import 'package:dart_console/dart_console.dart';

class ProgressBar {
  final String _title;
  final int _total;

  ProgressBar(this._title, this._total) {
    _render();
  }

  final _console = Console();
  var _currentProgress = 0;

  int get currentProgress => _currentProgress;

  void increment() {
    _currentProgress++;
    _render();
  }

  void _render() {
    if (_currentProgress > 0) {
      _console
        ..cursorUp()
        ..eraseLine();
    }

    var totalWidth = (_console.windowWidth * (45 / 100)).ceil();
    var progressWidth = ' ' * (totalWidth * (_currentProgress / _total)).ceil();
    _console
      ..write('$_title  ')
      ..setBackgroundColor(ConsoleColor.brightBlue)
      ..write(progressWidth)
      ..setBackgroundColor(ConsoleColor.brightBlack)
      ..write(' ' * (totalWidth - progressWidth.length))
      ..resetColorAttributes()
      ..writeLine('  (${(_currentProgress / _total * 100).ceil()}% done)');

    if (_currentProgress == _total) {
      _console.showCursor();
    }
  }
}
