import 'package:rush_cli/javac_errors/atse_errs.dart';
import 'package:rush_cli/javac_errors/computation_errs.dart';
import 'package:rush_cli/javac_errors/indentifier_errs.dart';
import 'package:rush_cli/javac_errors/return_errs.dart';
import 'package:rush_cli/javac_errors/syntax_errs.dart';

class ErrData {
  /// Returns the type of error.
  static int getNoOfLines(String err) {
    if (SyntaxErrs().isSyntaxErr(err).keys.first) {
      return SyntaxErrs().isSyntaxErr(err).values.first;
    } else if (IdentifierErrs().isIdentErr(err).keys.first) {
      return IdentifierErrs().isIdentErr(err).values.first;
    } else if (CompErrs().isCompErr(err).keys.first) {
      return CompErrs().isCompErr(err).values.first;
    } else if (ATSEErrs().isATSEErr(err).keys.first) {
      return ATSEErrs().isATSEErr(err).values.first;
    } else if (ReturnErrs().isReturnErr(err).keys.first) {
      return ReturnErrs().isReturnErr(err).values.first;
    } else {
      return null;
    }
  }
}
