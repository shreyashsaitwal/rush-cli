import 'package:rush_cli/javac_errors/err.dart';

/// Class for identifying computation errors.
class CompErrs extends Err {
  Map<bool, int> isCompErr(String msg) {
    final patterns = <List<dynamic>, RegExp>{
      ['varNotInit', 3]: RegExp(
          r'.*\.java:\d*:\serror:\svariable.*might\snot\shave\sbeen\sinitialized\s?',
          caseSensitive: true,
          dotAll: true),
      ['cantBeApplied', 3]: RegExp(
          r'.*\.java:\d*:\serror:.*in.*cannot\sbe\sapplied\sto.*',
          caseSensitive: true,
          dotAll: true),
      ['badOperand', 5]: RegExp(
          r'.*\.java:\d*:\serror:\sbad\soperand\stypes\sfor\sbinary\soperator.*',
          caseSensitive: true,
          dotAll: true),
      ['operatorCantBeApplied', 5]: RegExp(
          r'.*\.java:\d*:\serror:\soperator.*cannot\sbe\sapplied\sto.*',
          caseSensitive: true,
          dotAll: true),
      ['incompatibletypes', 3]: RegExp(
          r'.*\.java:\d*:\serror:\s(incompatible|inconvertible)\stypes:.*',
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
