import 'dart:io' show stdin, exit;

import 'package:dart_console/dart_console.dart';
import 'package:rush_prompt/src/questions/question.dart';

class SimpleQuestion extends Question {
  String? _question;
  String? _default;

  SimpleQuestion({
    required String question,
    required String id,
    String? defaultAnswer,
  }) {
    _question = question;
    this.id = id;
    _default = defaultAnswer;
  }

  @override
  List<dynamic> ask() {
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
    final answer = stdin.readLineSync();

    console.resetColorAttributes();

    if (answer == null) {
      exit(1);
    } else if (answer == '') {
      ask();
    }

    return [id, answer];
  }
}
