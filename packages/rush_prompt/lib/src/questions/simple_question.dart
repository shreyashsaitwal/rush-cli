import 'dart:io';

import 'package:dart_console/dart_console.dart';
import 'package:rush_prompt/src/questions/question.dart';

import 'package:meta/meta.dart';

class SimpleQuestion extends Question {
  String _question;
  String _default;

  String _prefix = '?';
  ConsoleColor _questionColor = ConsoleColor.white;
  ConsoleColor _prefixColor = ConsoleColor.green;
  ConsoleColor _answerColor = ConsoleColor.cyan;

  SimpleQuestion({
    @required String question,
    @required String id,
    String defaultAnswer,
  }) {
    _question = question;
    this.id = id;
    _default = defaultAnswer;
  }

  SimpleQuestion.fromMap(Map<String, dynamic> map) {
    _question = map['question'];
    this.id = map['id'];

    _prefix = map['prefix'] ?? '?';
    _default = map['default'];
    _questionColor = map['questionColor'] ?? ConsoleColor.white;
    _prefixColor = map['prefixColor'] ?? ConsoleColor.green;
    _answerColor = map['answerColor'] ?? ConsoleColor.cyan;
  }

  @override
  List<dynamic> ask() {
    console
      ..setForegroundColor(_prefixColor)
      ..write(_prefix == '' ? '' : '$_prefix ')
      ..setForegroundColor(_questionColor)
      ..write('$_question ');

    if (_default != null) {
      console
        ..setForegroundColor(ConsoleColor.brightBlack)
        ..write('($_default) ');
    }
    console.setForegroundColor(_answerColor);
    var answer = console.readLine(cancelOnBreak: true);

    if (_default == null && answer == '') {
      answer = ask()[1];
    } else if (_default != null) {
      answer = _default;
    }
    console.resetColorAttributes();

    if (answer == null) {
      console
        ..writeLine()
        ..writeLine()
        ..setForegroundColor(ConsoleColor.yellow)
        // ..write('[WARNING] ')
        ..writeLine('Task aborted by user.')
        ..resetColorAttributes();
        
      exit(1);
    }

    return [id, answer];
  }
}
