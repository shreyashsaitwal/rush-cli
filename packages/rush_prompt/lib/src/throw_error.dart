import 'dart:io';

import 'package:dart_console/dart_console.dart';
import 'package:meta/meta.dart';

class ThrowError {
  ThrowError({
    @required String message,
  }) {
    final console = Console();
    console
      ..writeLine()
      ..setForegroundColor(ConsoleColor.red)
      ..writeErrorLine(message)
      ..resetColorAttributes();
    exit(1);
  }
}
