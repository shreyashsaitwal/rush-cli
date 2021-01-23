import 'package:dart_console/dart_console.dart';
import 'package:rush_cli/javac/err.dart';

class SyntaxErr extends Err {
  @override
  int get noOfLines => 3;

  static bool isSyntaxErr(String msg) {
    final patterns = <String, RegExp>{
      'expected': RegExp(r".*\.java:\d*:\serror:\s('.*'|.*)\sexpected", caseSensitive: true, dotAll: true),
      'unclosedStrLit': RegExp(r'.*\.java:\d*:\serror:\sunclosed\sstring\sliteral', caseSensitive: true, dotAll: true),
      'illSrtOf': RegExp(r'.*\.java:\d*:\serror:\sillegal\sstart\sof\s(type|expression)', caseSensitive: true, dotAll:  true),
      'notAStatmnt': RegExp(r'.*\.java:\d*:\serror:\snot\sa\sstatement\s', caseSensitive: true, dotAll: true),
    };

    var isMatch = false;
    for (final exp in patterns.entries) {
      if (exp.value.hasMatch(msg)) {
        isMatch = true;
        break;
      }
    }
    return isMatch;
  }

  @override
  void printToConsole(List msg) {
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
