import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:collection/collection.dart';
import 'package:path/path.dart' as p;
import 'package:rush/src/commands/build/android_manifest.dart';

final _fontFile =
    RegExp(r'^res/font((?:-[^/]+)?)/([^/.]+)\.(ttf|otf|ttc|xml)$');
final _rawOrXmlFile = RegExp(r'^res/(raw|xml)(?:-[^/]+)?/([^/.]+)\.');
final _fontReference = RegExp(r'@([\w.]+:)?font/(\w+)');
final _fontRow = RegExp(r'^int font (\w+) ', multiLine: true);
const _sameBytes = ListEquality<int>();

class FontShim {
  const FontShim(this.package, this.kinds);

  final String package;
  final Map<String, String> kinds;

  String get source => [
        'package $package;',
        '',
        'public final class R {',
        for (final kind in {...kinds.values}) ...[
          '  public static final class $kind {',
          for (final MapEntry(key: name, value: fieldKind) in kinds.entries)
            if (fieldKind == kind) '    public static int $name;',
          '  }',
        ],
        '  public static final class font {',
        for (final MapEntry(key: name, value: kind) in kinds.entries)
          '    public static int $name = $kind.$name;',
        '  }',
        '}',
        '',
      ].join('\n');
}

class RawFonts {
  const RawFonts(this.libraries, this.shims);

  final Map<String, Archive> libraries;
  final Map<String, FontShim> shims;
}

RawFonts moveFontsToRaw(Map<String, Archive> libraries) {
  final kinds = {
    for (final library in libraries.values)
      for (final file in library.files)
        if (_fontFile.firstMatch(file.name) case final match?)
          match[2]!: match[3] == 'xml' ? 'xml' : 'raw',
  };
  if (kinds.isEmpty) {
    return const RawFonts({}, {});
  }
  _checkClashes(libraries, kinds);

  final changed = <String, Archive>{};
  final shims = <String, FontShim>{};
  for (final MapEntry(key: fileName, value: library) in libraries.entries) {
    final retyped = <String, String>{};
    final archive = Archive();
    var modified = false;
    for (final file in library.files.where((el) => el.isFile)) {
      final name = _movedName(file.name, kinds) ?? file.name;
      final content = switch (name) {
        'R.txt' => _retypeFontRows(file.content, kinds, retyped),
        _ when p.extension(name) == '.xml' =>
          _rewriteReferences(file.content, kinds),
        _ => file.content,
      };
      modified |=
          name != file.name || !_sameBytes.equals(content, file.content);
      archive.add(ArchiveFile.bytes(name, content));
    }
    if (!modified) continue;
    changed[fileName] = archive;
    if (retyped.isNotEmpty) {
      shims[fileName] = FontShim(_package(library, fileName), retyped);
    }
  }
  return RawFonts(changed, shims);
}

String? _movedName(String name, Map<String, String> kinds) {
  final match = _fontFile.firstMatch(name);
  return match == null
      ? null
      : 'res/${kinds[match[2]]}${match[1]}/${match[2]}.${match[3]}';
}

List<int> _retypeFontRows(List<int> symbols, Map<String, String> kinds,
        Map<String, String> retyped) =>
    utf8.encode(utf8.decode(symbols).replaceAllMapped(_fontRow, (match) {
      final kind = kinds[match[1]];
      if (kind == null) return match[0]!;
      retyped[match[1]!] = kind;
      return 'int $kind ${match[1]} ';
    }));

List<int> _rewriteReferences(List<int> xml, Map<String, String> kinds) =>
    utf8.encode(utf8.decode(xml).replaceAllMapped(_fontReference, (match) {
      final kind = kinds[match[2]];
      return kind == null ? match[0]! : '@${match[1] ?? ''}$kind/${match[2]}';
    }));

void _checkClashes(Map<String, Archive> libraries, Map<String, String> kinds) {
  for (final MapEntry(key: fileName, value: library) in libraries.entries) {
    for (final file in library.files) {
      final match = _rawOrXmlFile.firstMatch(file.name);
      if (match != null && kinds[match[2]] == match[1]) {
        throw Exception(
            'Font ${match[2]} would replace ${file.name} in $fileName when '
            'moved to res/${match[1]} for Kodular. Rename one of them.');
      }
    }
  }
}

String _package(Archive library, String fileName) {
  final manifest = library.findFile('AndroidManifest.xml');
  final package =
      manifest == null ? null : manifestPackage(utf8.decode(manifest.content));
  return package ??
      (throw Exception('$fileName has font resources but no manifest package'));
}
