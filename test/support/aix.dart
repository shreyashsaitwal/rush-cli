import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:test/test.dart';

class Aix {
  Aix(File file, this.package)
      : _archive = ZipDecoder().decodeBytes(file.readAsBytesSync());

  final Archive _archive;
  final String package;

  late final Set<String> entries = {
    for (final file in _archive.files)
      if (file.isFile) file.name.substring(package.length + 1)
  };

  List<int> bytes(String entry) =>
      _archive.findFile('$package/$entry')!.content;

  String text(String entry) => utf8.decode(bytes(entry));

  late final Set<String> classNames = {
    for (final file
        in ZipDecoder().decodeBytes(bytes('files/AndroidRuntime.jar')).files)
      file.name
  };

  Archive library(String fileName) =>
      ZipDecoder().decodeBytes(bytes('aars/$fileName'));

  late final Map<String, dynamic> buildInfo =
      (jsonDecode(text('files/component_build_infos.json')) as List).single
          as Map<String, dynamic>;

  List<String> get libraries => buildInfo['libraries'].cast<String>();

  late final List<Map<String, dynamic>> components =
      (jsonDecode(text('components.json')) as List)
          .cast<Map<String, dynamic>>();

  Map<String, dynamic> get component => components.single;
}

Matcher ships(String entry) => _Ships(entry);

class _Ships extends CustomMatcher {
  _Ships(String entry) : super('an AIX shipping', 'entries', contains(entry));

  @override
  Object? featureValueOf(Object? actual) => (actual as Aix).entries;
}
