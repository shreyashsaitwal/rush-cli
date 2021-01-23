import 'package:rush_cli/javac/err.dart';
import 'package:rush_cli/javac/syntax_err.dart';

enum ErrType { SYNTAX, IDENTIFIER, COMPUT, RETURN, ATS_ENTITIES, NONE }

class JParser {
  Err err;
  final List fullMsg = <String>[];
  final List nextMsg = <String>[];

  String _msg;
  set setMsg(String msg) => _msg = msg;

  void parse() {
    var sanitized = <String>[];
    if (nextMsg.isEmpty) {
      sanitized.addAll(_msg.replaceAll('[javac]:', '').split('\n').where((el) => el.contains(r'\S')));
      // .addAll(_msg.replaceAll('[javac]:', '').split('\n').map((el) {
      //   if (el.contains(r'\S')) {
      //     return el.trimRight();
      //   }
      // }));
    } else {
      sanitized = [...nextMsg];
      nextMsg.clear();
    }
    if (err == null && sanitized.isNotEmpty) {
      if (SyntaxErr.isSyntaxErr(sanitized.first)) {
        err = SyntaxErr();
        _incrementallyAdd(sanitized, err.noOfLines);
        if (fullMsg.length == err.noOfLines) {
          err.printToConsole(fullMsg);
          fullMsg.clear();
        }
      }
    } else if (sanitized.isNotEmpty) {
      _incrementallyAdd(sanitized, err.noOfLines);
      if (fullMsg.length == err.noOfLines) {
        err.printToConsole(fullMsg);
        fullMsg.clear();
        err = null;
      }
    }
  }

  void _incrementallyAdd(List list, int maxLength) {
    var length = list.length > maxLength ? maxLength : list.length;
    for (var i = 0; i < length; i++) {
      fullMsg.add(list[i]);
    }
    if (length == maxLength) {
      for (var i = length - 1; i < list.length; i++) {
        nextMsg.add(list[i]);
      }
    }
  }
}
