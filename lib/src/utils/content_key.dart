import 'dart:convert';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

class ContentKey {
  final _parts = <String>[];

  void add(String label, Object value) => _parts.add('$label $value');

  Future<void> addFile(String label, String path) async =>
      add(label, sha256.convert(await File(path).readAsBytes()));

  Future<void> addPath(String label, String path) async {
    if (await FileSystemEntity.isDirectory(path)) {
      final files = Directory(path)
          .listSync(recursive: true)
          .whereType<File>()
          .map((el) => el.path)
          .sortedBy(
              (el) => p.posix.joinAll(p.split(p.relative(el, from: path))));
      for (final file in files) {
        await addFile(
            '$label/${p.posix.joinAll(p.split(p.relative(file, from: path)))}',
            file);
      }
    } else if (await File(path).exists()) {
      await addFile(label, path);
    } else {
      add(label, 'missing');
    }
  }

  String get value => sha256.convert(utf8.encode(_parts.join('\n'))).toString();
}
