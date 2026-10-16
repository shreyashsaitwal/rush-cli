import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

import 'package:rush/src/commands/build/android_manifest.dart';
import 'package:rush/src/commands/build/android_xml.dart';

extension AarContents on Archive {
  String? text(String name) => switch (findFile(name)) {
        final file? => utf8.decode(file.content),
        null => null,
      };

  String? get package => manifestPackage(text('AndroidManifest.xml') ?? '');
}

bool isResourceXml(String entry) => switch (p.posix.split(entry)) {
      ['res', final directory, _] =>
        !directory.startsWith('raw') && p.posix.extension(entry) == '.xml',
      _ => false,
    };

XmlDocument resourceDocument(ArchiveFile file) {
  try {
    return parseAndroidXml(utf8.decode(file.content));
  } on XmlException catch (e) {
    throw FormatException('${file.name}: ${e.message}');
  }
}

Iterable<({String type, String name})> rTxtRows(String rTxt) =>
    const LineSplitter()
        .convert(rTxt)
        .map((line) => line.split(' '))
        .where((parts) => parts.length >= 3)
        .map((parts) => (type: parts[1], name: parts[2]));
