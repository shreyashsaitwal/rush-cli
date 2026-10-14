import 'package:collection/collection.dart';

import 'package:rush/src/commands/migrate/comments.dart';

final _rushRule = RegExp(
    r'^\s*(-repackageclasses\b|-keeppackagenames gnu\.kawa\*\*, gnu\.expr\*\*\s*$)');

String withoutRushRules(String rules) =>
    withoutCommentsAbove(rules, _rushRule.hasMatch)
        .split('\n')
        .whereNot(_rushRule.hasMatch)
        .join('\n')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .replaceFirst(RegExp(r'\n+$'), '\n');
