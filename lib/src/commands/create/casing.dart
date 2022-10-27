class Casing {
  /// Converts the [input] to PascalCase.
  static String pascalCase(String input) {
    final processed = _process(input);
    var result = '';
    for (final word in processed) {
      final firstLetter = word.split('').first;
      result += word.replaceFirst(firstLetter, firstLetter.toUpperCase());
    }
    return result;
  }

  /// Converts the [input] to camelCase.
  static String camelCase(String input) {
    final processed = _process(input);
    var result = '';
    var isFirst = true;
    for (final word in processed) {
      final firstLetter = word.split('').first;
      if (isFirst) {
        result += word.replaceFirst(firstLetter, firstLetter.toLowerCase());
        isFirst = false;
      } else {
        result += word.replaceFirst(firstLetter, firstLetter.toUpperCase());
      }
    }
    return result;
  }

  /// Converts the [input] to kebab-case.
  static String kebabCase(String input) {
    final processed = _process(input);
    var result = '';
    var isFirst = true;
    for (final word in processed) {
      final firstLetter = word.split('').first;
      if (!isFirst) {
        result +=
            word.replaceFirst(firstLetter, '-${firstLetter.toLowerCase()}');
      } else {
        isFirst = false;
        result += word.replaceFirst(firstLetter, firstLetter.toLowerCase());
      }
    }
    return result;
  }

  /// Processes the given input
  static List<String> _process(String input) {
    final words = <String>[];

    final capital = RegExp('[A-Z]');
    final separator = RegExp(r'[\s-_]');

    var isFirst = true;
    var gotSpace = false;

    for (final char in input.split('')) {
      if (gotSpace) {
        gotSpace = false;
        words.add(char);
      } else if (!isFirst) {
        if (capital.hasMatch(char)) {
          words.add(char);
        } else if (separator.hasMatch(char)) {
          gotSpace = true;
        } else {
          final word = words.last + char;
          words.removeLast();
          words.add(word);
        }
      } else {
        words.add(char);
        isFirst = false;
      }
    }

    return words;
  }
}
