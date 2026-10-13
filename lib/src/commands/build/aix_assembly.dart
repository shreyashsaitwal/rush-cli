import 'dart:convert' show jsonEncode, utf8;
import 'dart:io' show File;

import 'package:archive/archive_io.dart';
import 'package:get_it/get_it.dart';
import 'package:path/path.dart' as p;
import 'package:tint/tint.dart';

import 'package:rush/src/commands/build/aix.dart';
import 'package:rush/src/commands/build/descriptor.dart';
import 'package:rush/src/commands/build/docs.dart';
import 'package:rush/src/config/config.dart';
import 'package:rush/src/services/file_service.dart';
import 'package:rush/src/services/logger.dart';
import 'package:rush/src/utils/file_extension.dart';
import 'package:rush/src/utils/zip.dart';

final _fs = GetIt.I<FileService>();
final _lgr = GetIt.I<Logger>();

Future<void> assembleAix(
    Config config, Descriptor descriptor, List<Library> libraries) async {
  final org = descriptor.package;
  final components = descriptor.components;
  final buildInfos = [
    for (final info in descriptor.buildInfos)
      {...info, 'libraries': libraries.map((el) => el.fileName).toList()},
  ];
  final generated = {
    'files/component_build_infos.json': utf8.encode(jsonEncode(buildInfos)),
    for (final library in libraries) 'aars/${library.fileName}': library.bytes,
  };

  final outputDir = p.join(_fs.cwd, 'out').asDir(true);
  final aix = p.join(outputDir.path, '$org.aix');
  await writeZip(aix, [
    for (final entry in aixEntries(components, buildInfos))
      ArchiveFile.bytes('$org/$entry',
          generated[entry] ?? await _entrySource(config, entry).readAsBytes()),
  ]);
  _lgr.info('Generated AIX file at ${aix.blue()}');

  final docs = p.join(outputDir.path, '$org.md');
  await docs.asFile().writeAsString(markdownDocs(components));
  _lgr.info('Generated docs at ${docs.blue()}');
}

File _entrySource(Config config, String entry) => switch (entry) {
      'aiwebres/LICENSE' => p.join(_fs.cwd, config.license).asFile(),
      _ when entry.startsWith('assets/') => p.join(_fs.cwd, entry).asFile(),
      _ => p.join(_fs.buildRawDir.path, entry).asFile(),
    };
