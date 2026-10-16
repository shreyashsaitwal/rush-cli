import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

import 'package:rush/src/commands/build/android_manifest.dart';

extension AarContents on Archive {
  String? text(String name) => switch (findFile(name)) {
        final file? => utf8.decode(file.content),
        null => null,
      };

  String? get package => manifestPackage(text('AndroidManifest.xml') ?? '');
}

bool isResourceXml(String entry) =>
    entry.startsWith('res/') && p.posix.extension(entry) == '.xml';

Iterable<({String type, String name})> rTxtRows(String rTxt) =>
    const LineSplitter()
        .convert(rTxt)
        .map((line) => line.split(' '))
        .where((parts) => parts.length >= 3)
        .map((parts) => (type: parts[1], name: parts[2]));
