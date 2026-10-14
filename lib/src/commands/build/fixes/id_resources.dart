import 'dart:convert';

import 'package:archive/archive.dart';

final _valuesFile = RegExp(r'^res/values[^/]*/[^/]+\.xml$');
final _shortId = RegExp(r'<id(\s[^>]*?)\s*(?:/>|>\s*</id>)');

Map<String, Archive> withLongIdResources(Map<String, Archive> libraries) => {
      for (final MapEntry(key: fileName, value: library) in libraries.entries)
        if (library.files.any(_hasShortIds)) fileName: _withLongIds(library),
    };

bool _hasShortIds(ArchiveFile file) =>
    _valuesFile.hasMatch(file.name) &&
    _shortId.hasMatch(utf8.decode(file.content));

Archive _withLongIds(Archive library) {
  final archive = Archive();
  for (final file in library.files.where((el) => el.isFile)) {
    archive.add(_hasShortIds(file)
        ? ArchiveFile.string(
            file.name,
            utf8.decode(file.content).replaceAllMapped(
                _shortId, (match) => '<item${match[1]} type="id"/>'))
        : file);
  }
  return archive;
}
