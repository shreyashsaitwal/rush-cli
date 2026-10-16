import 'dart:convert';

import 'package:collection/collection.dart';

import 'package:rush/src/commands/build/resource_names.dart';

final _styleableArray = RegExp(r'^int\[\] styleable (\S+) \{(.*)\}$');

String ownSymbols(String rTxt, ResourceDefinitions own) {
  final fields = {
    for (final (type, name) in own.defined) (type, resourceField(name)),
  };
  final styleables = [
    for (final (type, name) in own.defined)
      if (type == 'styleable') resourceField(name),
  ];
  bool isOwn(List<String> parts) => switch (parts) {
        ['int[]', 'styleable', final name, ...] => styleables.contains(name),
        ['int', 'styleable', final name, ...] =>
          styleables.any((el) => name.startsWith('${el}_')),
        [_, final type, final name, ...] => fields.contains((type, name)),
        _ => false,
      };
  return const LineSplitter()
      .convert(rTxt)
      .where((line) => isOwn(line.split(' ')))
      .map((line) => '$line\n')
      .join();
}

String rClass(String package, String rTxt) {
  final types = const LineSplitter()
      .convert(rTxt)
      .where((line) => line.isNotEmpty)
      .groupListsBy((line) => line.split(' ')[1]);
  return [
    'package $package;\n',
    '\n',
    'public final class R {\n',
    for (final MapEntry(key: type, value: lines) in types.entries) ...[
      '  public static final class $type {\n',
      for (final line in lines) _field(line),
      '  }\n',
    ],
    '}\n',
  ].join();
}

String _field(String line) {
  if (_styleableArray.firstMatch(line) case final array?) {
    return '    public static final int[] ${array[1]}={\n'
        '      ${array[2]!.trim()}\n'
        '    };\n';
  }
  final [_, _, name, value] = line.split(' ');
  return '    public static int $name=$value;\n';
}
