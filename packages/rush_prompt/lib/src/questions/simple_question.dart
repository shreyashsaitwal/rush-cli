import 'dart:io' show stdin, exit;

import 'package:dart_console/dart_console.dart';
import 'package:rush_prompt/src/questions/question.dart';

class SimpleQuestion extends Question {
  String? _question;
  String? _default;

  SimpleQuestion({
    required String question,
    String? defaultAnswer,
  }) {
    _question = question;
    _default = defaultAnswer;
  }

  @override
  String ask() {
    console
      ..setForegroundColor(ConsoleColor.green)
      ..write('? ')
      ..resetColorAttributes()
      ..write('$_question ');

    if (_default != null) {
      console
        ..setForegroundColor(ConsoleColor.brightBlack)
        ..write('($_default) ');
    }
    console.setForegroundColor(ConsoleColor.cyan);
    var answer = stdin.readLineSync();

    console.resetColorAttributes();

    if (answer == null) {
      console
        ..writeLine()
        ..writeLine()
        ..setForegroundColor(ConsoleColor.yellow)
        ..writeLine('Task aborted by user.')
        ..resetColorAttributes();

      exit(1);
    } else if (answer == '') {
      ask();
    }

    return answer.trim();
  }
}
