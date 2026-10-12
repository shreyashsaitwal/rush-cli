import 'dart:io' show File;

import 'package:archive/archive.dart';
import 'package:collection/collection.dart';
import 'package:path/path.dart' as p;

import 'package:rush/src/utils/file_extension.dart';

final _modified = DateTime(1980);
const _fileMode = 0x1a4;

Future<void> writeZip(String path, Iterable<ArchiveFile> entries) async {
  final archive = Archive();
  for (final entry in entries.sortedBy((entry) => entry.name)) {
    if (entry.isFile) {
      entry.mode = _fileMode;
    }
    archive.add(entry);
  }
  await path
      .asFile(true)
      .writeAsBytes(ZipEncoder().encodeBytes(archive, modified: _modified));
}

Future<ArchiveFile> fileEntry(File file, {required String from}) async =>
    ArchiveFile.bytes(
        p.posix.joinAll(p.split(p.relative(file.path, from: from))),
        await file.readAsBytes());
