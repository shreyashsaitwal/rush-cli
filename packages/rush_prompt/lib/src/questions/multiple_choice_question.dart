import 'dart:io' show exit;

import 'package:dart_console/dart_console.dart';

import '../questions/question.dart';

class MultipleChoiceQuestion extends Question {
  String? _question;
  late List<String> _options;
  String? _id;
  String? _hint;

  MultipleChoiceQuestion({
    required String question,
    required List<String> options,
    required String id,
    String? hint,
    String? defaultAnswer,
  }) {
    _question = question;
    _id = id;
    _options = options;

    _hint = hint ?? '(Use arrow or \'W\'/\'S\' keys to navigate & press enter to select)';
  }

  void _renderList(int activeIndex) {
    for (final option in _options) {
      if (activeIndex == _options.indexOf(option)) {
        console
          ..setForegroundColor(ConsoleColor.cyan)
          ..writeLine('❯ $option')
          ..resetColorAttributes();
      } else {
        console.writeLine(' ' * 2 + option);
      }
    }
  }

  void _clearList() {
    for (final _ in _options) {
      console
        ..cursorUp()
        ..eraseLine();
    }
  }

  @override
  List ask() {
    var activeIndex = 0;

    console
      ..setForegroundColor(ConsoleColor.green)
      ..write('? ')
      ..resetColorAttributes()
      ..write('$_question ')
      ..setForegroundColor(ConsoleColor.brightBlack)
      ..writeLine(_hint == '' ? '' : '$_hint ');

    _renderList(activeIndex);

    var key = console.readKey();
    while (true) {
      if (_isDown(key) && activeIndex < _options.length - 1) {
        _clearList();
        activeIndex++;
        _renderList(activeIndex);
      } else if (_isUp(key) && activeIndex > 0) {
        _clearList();
        activeIndex--;
        _renderList(activeIndex);
      } else if (key.controlChar == ControlCharacter.ctrlC) {
        exit(1);
      } else if (key.controlChar == ControlCharacter.enter) {
        return [_id, _options[activeIndex]];
      }
      key = console.readKey();
    }
  }

  bool _isUp(Key key) {
    return key.controlChar == ControlCharacter.arrowUp ||
        key.char.toLowerCase() == 'w';
  }

  bool _isDown(Key key) {
    return key.controlChar == ControlCharacter.arrowDown ||
        key.char.toLowerCase() == 's';
  }
}
