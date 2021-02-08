import 'package:dart_console/dart_console.dart';

class BuildStep {
  final console = Console();

  final String _title;

  BuildStep(this._title);

  void init() {
    console
      ..setForegroundColor(ConsoleColor.brightBlack)
      ..write('┌ ')
      ..resetColorAttributes()
      ..setForegroundColor(ConsoleColor.brightWhite)
      ..writeLine(_title)
      ..resetColorAttributes();
  }

  void add(String msg, ConsoleColor clr,
      {bool addSpace = false,
      String prefix = '',
      ConsoleColor prefClr = ConsoleColor.white,
      ConsoleColor prefBgClr = ConsoleColor.black}) {
    if (addSpace) {
      console
        ..setForegroundColor(ConsoleColor.brightBlack)
        ..writeLine('│ ')
        ..resetColorAttributes();
    }
    console
      ..setForegroundColor(ConsoleColor.brightBlack)
      ..write('│ ')
      ..resetColorAttributes();

    if (prefix != '' && prefBgClr != ConsoleColor.black) {
      console
        ..write(' ')
        ..setBackgroundColor(prefBgClr)
        ..setForegroundColor(prefClr)
        ..write(prefix)
        ..resetColorAttributes()
        ..write(' ')
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
      ..setForegroundColor(ConsoleColor.brightBlack)
      ..write('└ ')
      ..resetColorAttributes()
      ..setForegroundColor(clr)
      ..writeLine(msg)
      ..resetColorAttributes();
  }
}
