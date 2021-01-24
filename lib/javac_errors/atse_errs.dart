import 'package:rush_cli/javac_errors/err.dart';

/// Class for identifying ATSE (access to static entities) errors.
class ATSEErrs extends Err {
  Map<bool, int> isATSEErr(String msg) {
    final patterns = <String, RegExp>{
      'nonStaticRef': RegExp(
          r'.*\.java:\d*:\serror:\snon-static\s(variable|method).*cannot\sbe\sreferenced\sfrom\sa\sstatic\scontext\s?',
          caseSensitive: true,
          dotAll: true),
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
