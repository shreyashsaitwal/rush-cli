import 'dart:io';

import 'package:dart_console/dart_console.dart';
import 'package:meta/meta.dart';

import '../questions/question.dart';

class MultipleChoiceQuestion extends Question {
  String _question;
  List<String> _options;
  String _id;
  String _hint;

  MultipleChoiceQuestion({
    @required String question,
    @required List<String> options,
    @required String id,
    String hint,
    String defaultAnswer,
  }) {
    _question = question;
    _id = id;
    _options = options;

    _hint = hint ??
        '(Use arrow keys to navigate to the correct option & enter to select it.)';
  }

  void _renderList(int activeIndex) {
    _options.forEach((option) {
      if (activeIndex == _options.indexOf(option)) {
        console
          ..setForegroundColor(ConsoleColor.cyan)
          ..writeLine('› $option')
          ..resetColorAttributes();
      } else {
        console.writeLine('  $option');
      }
    });
  }

  void _clearList() {
    _options.forEach((element) {
      console
        ..cursorUp()
        ..eraseLine();
    });
  }

  @override
  List ask() {
    var activeIndex = 0;

    console
      ..setForegroundColor(ConsoleColor.green)
      ..write('? ')
      ..setForegroundColor(ConsoleColor.white)
      ..write('$_question ')
      ..setForegroundColor(ConsoleColor.brightBlack)
      ..writeLine(_hint == '' ? '' : '$_hint ');

    _renderList(activeIndex);

    var key = console.readKey().controlChar;
    while (true) {
      if (key == ControlCharacter.arrowDown &&
          activeIndex < _options.length - 1) {
        _clearList();
        activeIndex++;
        _renderList(activeIndex);
      } else if (key == ControlCharacter.arrowUp && activeIndex > 0) {
        _clearList();
        activeIndex--;
        _renderList(activeIndex);
      } else if (key == ControlCharacter.ctrlC) {
        console
          ..writeLine()
          ..writeLine()
          ..setForegroundColor(ConsoleColor.yellow)
          ..writeLine('Task aborted by user.')
          ..resetColorAttributes();
        exit(1);
      } else if (key == ControlCharacter.enter) {
        return [_id, _options[activeIndex]];
      }
      key = console.readKey().controlChar;
    }
  }
}
