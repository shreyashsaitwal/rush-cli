import 'package:dart_console/dart_console.dart';

class ProgressBar {
  ProgressBar(this._title);

  final String _title;
  final console = Console();

  int totalProgress;

  void update(int currentProgress) {
    if (currentProgress > 0) {
      console
        ..cursorUp()
        ..eraseLine();
    }

    var totalWidth = (console.windowWidth * (45 / 100)).ceil();
    var progressWidth = ' ' * (totalWidth * (currentProgress / totalProgress)).ceil();
    console
      ..hideCursor()
      ..write('$_title  ')
      ..setBackgroundColor(ConsoleColor.brightBlue)
      ..write(progressWidth)
      ..setBackgroundColor(ConsoleColor.brightBlack)
      ..write(' ' * (totalWidth - progressWidth.length))
      ..resetColorAttributes()
      ..writeLine('  (${(currentProgress / totalProgress * 100).ceil()}% done)');

    if (currentProgress == totalProgress) {
      console.showCursor();
    }
  }
}