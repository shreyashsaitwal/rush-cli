import 'dart:convert';
import 'dart:io' show File;

import 'package:archive/archive_io.dart';
import 'package:get_it/get_it.dart';
import 'package:path/path.dart' as p;
import 'package:tint/tint.dart';

import 'package:rush/src/commands/build/aix.dart';
import 'package:rush/src/commands/build/android_manifest.dart';
import 'package:rush/src/commands/build/private_names.dart';
import 'package:rush/src/commands/build/tools/executor.dart';
import 'package:rush/src/config/config.dart';
import 'package:rush/src/services/file_service.dart';
import 'package:rush/src/services/logger.dart';
import 'package:rush/src/utils/file_extension.dart';
import 'package:rush/src/utils/zip.dart';

class ExtensionResources {
  ExtensionResources._(this.package, this._dir);

  static final _fs = GetIt.I<FileService>();
  static final _lgr = GetIt.I<Logger>();

  final String package;
  final String _dir;

  String get classesDir => p.join(_dir, 'classes');

  String get classesJar => p.join(_dir, 'classes.jar');

  String get _symbols => p.join(_dir, 'R.txt');

  String get _manifest => p.join(_dir, 'AndroidManifest.xml');

  static Future<ExtensionResources?> compile(Config config) async {
    if (!await _fs.resDir.exists()) {
      return null;
    }

    final dir = p.join(_fs.buildFilesDir.path, 'resources').asDir();
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
    await dir.create(recursive: true);
    final resources = ExtensionResources._(await _manifestPackage(), dir.path);
    await resources._manifest.asFile().writeAsString('''
<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="${resources.package}">
  <uses-sdk android:minSdkVersion="${config.minSdk}"/>
</manifest>
''');

    final compiled = p.join(dir.path, 'compiled.zip');
    final javaDir = p.join(dir.path, 'java');
    await Executor.execAapt2Compile(resDir: _fs.resDir.path, output: compiled);
    await Executor.execAapt2Link(
      manifest: resources._manifest,
      compiledResources: compiled,
      javaDir: javaDir,
      symbols: resources._symbols,
      output: p.join(dir.path, 'resources.apk'),
    );
    await resources._checkNames();
    await Executor.execJavac(
      sources: javaDir
          .asDir()
          .listSync(recursive: true)
          .whereType<File>()
          .map((el) => el.path)
          .toSet(),
      output: resources.classesDir,
    );
    await writeZip(resources.classesJar, [
      for (final file in resources.classesDir
          .asDir()
          .listSync(recursive: true)
          .whereType<File>())
        await fileEntry(file, from: resources.classesDir),
    ]);
    return resources;
  }

  static Future<String> _manifestPackage() async {
    final manifest = p.join(_fs.srcDir.path, 'AndroidManifest.xml').asFile();
    final package = manifestPackage(await manifest.readAsString());
    if (package == null) {
      _lgr.err('src/AndroidManifest.xml must declare the extension package '
          'to use resources');
      throw Exception();
    }
    return package;
  }

  Future<void> _checkNames() async {
    final prefix = '${package.toLowerCase().replaceAll('.', '_')}_';
    final reserved = PrivateNames.resourcePrefix(package);
    final problems = {
      for (final line in await _symbols.asFile().readAsLines())
        if (line.split(' ') case [_, final type, final name, ...]
            when type != 'id')
          if (!name.startsWith(prefix))
            '$type/$name must be named $prefix$name'
          else if (name.startsWith(reserved))
            "$type/$name can't start with $reserved, which Rush gives the "
                'resources of private libraries',
    };
    if (problems.isEmpty) {
      return;
    }
    problems.forEach(_lgr.err);
    _lgr.log(
        'Resource names start with the extension package so they never clash '
        'with other extensions or App Inventor',
        'help  '.green());
    throw Exception();
  }

  Future<List<String>> xml() async => [
        for (final file in _files.where(_isXml)) await file.readAsString(),
      ];

  Future<Library> packageAar(PrivateNames names) async => Library(
      '$package.aar',
      zipBytes([
        ArchiveFile.bytes(
            'AndroidManifest.xml', await _manifest.asFile().readAsBytes()),
        ArchiveFile.bytes('R.txt', await _symbols.asFile().readAsBytes()),
        for (final file in _files) await _packaged(file, names),
      ]));

  Future<ArchiveFile> _packaged(File file, PrivateNames names) async {
    final entry = await fileEntry(file, from: _fs.resDir.parent.path);
    return _isXml(file)
        ? ArchiveFile.string(
            entry.name, names.renameClassReferences(utf8.decode(entry.content)))
        : entry;
  }

  Iterable<File> get _files =>
      _fs.resDir.listSync(recursive: true).whereType<File>();

  static bool _isXml(File file) => p.extension(file.path) == '.xml';
}
