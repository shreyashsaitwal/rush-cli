import 'package:dart_console/dart_console.dart';
import 'package:rush_cli/javac/err.dart';

class SyntaxErr {
  static const int noOfLines = 3;

  static List isSyntaxErr(String msg) {
    final patterns = <String, RegExp>{
      'expected': RegExp(r".*\.java:\d*:\serror:\s('.*'|.*)\sexpected", caseSensitive: true, dotAll: true),
      'unclosedStrLit': RegExp(r'.*\.java:\d*:\serror:\sunclosed\sstring\sliteral', caseSensitive: true, dotAll: true),
      'illSrtOf': RegExp(r'.*\.java:\d*:\serror:\sillegal\sstart\sof\s(type|expression)', caseSensitive: true, dotAll:  true),
      'notAStatmnt': RegExp(r'.*\.java:\d*:\serror:\snot\sa\sstatement\s', caseSensitive: true, dotAll: true),
    };

    var type;
    var isMatch = false;
    for (final exp in patterns.entries) {
      if (exp.value.hasMatch(msg)) {
        isMatch = true;
        type = exp.key;
        break;
      }
    }
    return [isMatch, type];
  }

  static void printToConsole(List msg) {
    if (msg.length > noOfLines) {
      throw 'Length of the message for error type "SyntaxErr" should not be any greater than $noOfLines';
    }

    final console = Console();
    console.setForegroundColor(ConsoleColor.red);
    msg.forEach((ln) => console.writeErrorLine(ln));
    console
      ..resetColorAttributes()
      ..writeLine();
  }
}
