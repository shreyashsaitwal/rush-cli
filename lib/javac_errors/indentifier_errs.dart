import 'package:rush_cli/javac_errors/err.dart';

/// Class fro identifying identifier errors.
class IdentifierErrs extends Err {
  Map<bool, int> isIdentErr(String msg) {
    final patterns = <List<dynamic>, RegExp>{
      ['symbolNotFound', 5]: RegExp(
          r'.*\.java:\d*:\serror:\scannot\sfind\ssymbol\s?',
          caseSensitive: true,
          dotAll: true),
      ['alreadyDefined', 3]: RegExp(
          r'.*\.java:\d*:\serror:.*is\salready\sdefined\sin\s?',
          caseSensitive: true,
          dotAll: true),
      ['arrayRequired', 3]: RegExp(
          r'.*\.java:\d*:\serror:\sarray\srequired\sbut.*found\s?',
          caseSensitive: true,
          dotAll: true),
      ['privateAccess', 3]: RegExp(
          r'.*\.java:\d*:\serror:.*has\sprivate\saccess\sin.*\s?',
          caseSensitive: true,
          dotAll: true),
    };

    var isMatch = false;
    var noOfLines = 0;
    for (final exp in patterns.entries) {
      if (exp.value.hasMatch(msg)) {
        isMatch = true;
        noOfLines = exp.key[1];
        break;
      }
    }
    return {isMatch: noOfLines};
  }
}
