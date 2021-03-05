import 'package:dart_console/dart_console.dart';

class ProgressBar {
  final String _title;
  final _console = Console();

  ProgressBar(this._title);

  int? totalProgress;

  void update(int currentProgress) {
    if (currentProgress > 0) {
      _console
        ..cursorUp()
        ..eraseLine();
    }

    var totalWidth = (_console.windowWidth * (45 / 100)).ceil();
    var progressWidth =
        ' ' * (totalWidth * (currentProgress / totalProgress!)).ceil();
    _console
      ..hideCursor()
      ..setForegroundColor(ConsoleColor.brightWhite)
      ..write('$_title  ')
      ..setBackgroundColor(ConsoleColor.brightBlue)
      ..write(progressWidth)
      ..setBackgroundColor(ConsoleColor.brightBlack)
      ..write(' ' * (totalWidth - progressWidth.length))
      ..resetColorAttributes()
      ..writeLine(
          '  (${(currentProgress / totalProgress! * 100).ceil()}% done)');

    if (currentProgress == totalProgress) {
      _console.showCursor();
    }
  }
}
