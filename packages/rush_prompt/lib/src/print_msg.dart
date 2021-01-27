import 'package:dart_console/dart_console.dart';

class PrintMsg {
  final String _msg;
  ConsoleColor clr;
  String prefix;
  ConsoleColor prefClr;

  PrintMsg(this._msg,
      [this.clr = ConsoleColor.brightWhite,
      this.prefix = '',
      this.prefClr = ConsoleColor.cyan]) {
    _show();
  }

  void _show() {
    final console = Console();
    if (prefix != '') {
      console
        ..setForegroundColor(prefClr)
        ..write(prefix + ' ')
        ..resetColorAttributes();
    }
    console
      ..setForegroundColor(clr)
      ..writeLine(_msg)
      ..resetColorAttributes();
  }
}
