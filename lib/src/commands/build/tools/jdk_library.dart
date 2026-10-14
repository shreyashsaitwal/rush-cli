import 'dart:io' show pid;

import 'package:archive/archive_io.dart';
import 'package:get_it/get_it.dart';
import 'package:path/path.dart' as p;

import 'package:rush/src/commands/build/utils.dart';
import 'package:rush/src/services/file_service.dart';
import 'package:rush/src/utils/content_key.dart';
import 'package:rush/src/utils/file_extension.dart';
import 'package:rush/src/utils/zip.dart';

const _modules = ['java.base', 'java.compiler'];
const _jmodHeaderLength = 4;
const _classesPrefix = 'classes/';

Future<String> jdkLibrary() async {
  final javaHome = await BuildUtils.javaHomeDir();
  final key = ContentKey()..add('modules', _modules.join(','));
  await key.addFile('jdk', p.join(javaHome, 'release'));
  final dir = p.join(GetIt.I<FileService>().rushHomeDir.path, 'cache', 'jdk');
  final jar = p.join(dir, '${key.value}.jar');
  if (!await jar.asFile().exists()) {
    final partial = p.join(dir, '${key.value}.$pid.jar');
    await writeZip(partial, [
      for (final module in _modules)
        ...await _moduleClasses(p.join(javaHome, 'jmods', '$module.jmod')),
    ]);
    await partial.asFile().rename(jar);
  }
  return jar;
}

Future<List<ArchiveFile>> _moduleClasses(String jmod) async => [
      for (final file in ZipDecoder()
          .decodeBytes(
              (await jmod.asFile().readAsBytes()).sublist(_jmodHeaderLength))
          .files)
        if (file.isFile &&
            file.name.startsWith(_classesPrefix) &&
            file.name.endsWith('.class') &&
            file.name != '${_classesPrefix}module-info.class')
          ArchiveFile.bytes(
              file.name.substring(_classesPrefix.length), file.content),
    ];
