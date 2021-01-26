import 'package:dart_console/dart_console.dart';

class BuildStep {
  final console = Console();

  final String _title;
  final String _stepNum;

  BuildStep(this._title, this._stepNum);

  void init() {
    console
      ..setForegroundColor(ConsoleColor.cyan)
      ..write(_stepNum)
      ..resetColorAttributes()
      ..write(' ┌ ')
      ..setForegroundColor(ConsoleColor.brightWhite)
      ..writeLine(_title)
      ..resetColorAttributes();
  }

  void add(String msg, ConsoleColor clr, bool addSpace,
      {String prefix = '', ConsoleColor prefClr = ConsoleColor.black}) {
    if (addSpace) {
      console..writeLine(' ' * _stepNum.length + ' │ ');
    }
    console..write(' ' * _stepNum.length + ' │ ');

    if (prefix != '' && prefClr != ConsoleColor.black) {
      console
        ..write(' ')
        ..setBackgroundColor(prefClr)
        ..setForegroundColor(ConsoleColor.brightWhite)
        ..write(prefix)
        ..resetColorAttributes()
        ..setForegroundColor(clr)
        ..writeLine(msg)
        ..resetColorAttributes();
    } else {
      console
        ..setForegroundColor(clr)
        ..writeLine(' ' + msg)
        ..resetColorAttributes();
    }
  }

  void finish(String msg, ConsoleColor clr) {
    console
      ..write(' ' * _stepNum.length)
      ..write(' └─ ')
      ..setForegroundColor(clr)
      ..writeLine(msg)
      ..resetColorAttributes();
  }
}
