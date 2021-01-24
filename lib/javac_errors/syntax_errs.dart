import 'package:rush_cli/javac_errors/err.dart';

/// Class for identifying syntactic errors.
class SyntaxErrs extends Err {
  Map<bool, int> isSyntaxErr(String msg) {
    final patterns = <String, RegExp>{
      'expected': RegExp(r".*\.java:\d*:\serror:\s('.*'|.*)\sexpected",
          caseSensitive: true, dotAll: true),
      'unclosedStrLit': RegExp(
          r'.*\.java:\d*:\serror:\sunclosed\sstring\sliteral',
          caseSensitive: true,
          dotAll: true),
      'illSrtOf': RegExp(
          r'.*\.java:\d*:\serror:\sillegal\sstart\sof\s(type|expression)',
          caseSensitive: true,
          dotAll: true),
      'notAStatmnt': RegExp(r'.*\.java:\d*:\serror:\snot\sa\sstatement\s',
          caseSensitive: true, dotAll: true),
    };

    var isMatch = false;
    for (final exp in patterns.entries) {
      if (exp.value.hasMatch(msg)) {
        isMatch = true;
        break;
      }
    }
    return {isMatch: 3};
  }
}
