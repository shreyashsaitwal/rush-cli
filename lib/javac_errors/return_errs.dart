import 'package:rush_cli/javac_errors/err.dart';

/// Class for identifying return statement errors.
class ReturnErrs extends Err {
  Map<bool, int> isReturnErr(String msg) {
    final patterns = <String, RegExp>{
      'missingReturn': RegExp(
          r'.*\.java:\d*:\serror:\smissing\sreturn\sstatement\s?',
          caseSensitive: true,
          dotAll: true),
      'incompatibletypes': RegExp(
          r'.*\.java:\d*:\serror:\s(incompatible|inconvertible)\stypes:.*',
          caseSensitive: true,
          dotAll: true),
      'invalidMethDelc': RegExp(
          r'.*\.java:\d*:\serror:\sinvalid\smethod\sdeclaration;.*',
          caseSensitive: true,
          dotAll: true),
      'unreachable': RegExp(r'.*\.java:\d*:\serror:\sunreachable\sstatement\s?',
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
