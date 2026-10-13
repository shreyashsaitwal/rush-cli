import 'dart:io' show Platform;

import 'package:archive/archive_io.dart';
import 'package:get_it/get_it.dart';
import 'package:path/path.dart' as p;
import 'package:pool/pool.dart';

import 'package:rush/src/commands/build/aix.dart';
import 'package:rush/src/commands/build/build_dependencies.dart';
import 'package:rush/src/commands/build/fixes/raw_fonts.dart';
import 'package:rush/src/commands/build/libraries.dart';
import 'package:rush/src/commands/build/resources.dart';
import 'package:rush/src/commands/build/tools/executor.dart';
import 'package:rush/src/commands/build/tools/library_desugarer.dart';
import 'package:rush/src/commands/build/utils.dart';
import 'package:rush/src/config/config.dart';
import 'package:rush/src/resolver/artifact.dart';
import 'package:rush/src/services/file_service.dart';
import 'package:rush/src/services/logger.dart';
import 'package:rush/src/utils/file_extension.dart';
import 'package:rush/src/utils/zip.dart';

final _fs = GetIt.I<FileService>();
final _lgr = GetIt.I<Logger>();

Future<List<Library>> packageLibraries(Config config, BuildDependencies deps,
    ExtensionResources? resources) async {
  final pool = Pool(Platform.numberOfProcessors.clamp(1, 4));
  final sharedClasses = await _sharedJarClasses(deps.sharedJars);
  final desugarer = LibraryDesugarer(config);
  final libraries = await Future.wait([
    ...deps.shippedAars.map(
        (aar) => pool.withResource(() => _packageAar(desugarer, aar, deps))),
    ...sharedClasses.entries.map((el) => pool.withResource(
        () => _packageSharedJar(config, desugarer, el.key, el.value, deps))),
    if (resources != null) resources.packageAar(),
  ]);

  if (libraries.isNotEmpty) {
    _lgr.info('Packaged ${libraries.length} AAR(s): '
        '${libraries.map((el) => el.fileName).join(', ')}');
  }
  return libraries;
}

Future<List<Library>> moveLibraryFontsToRaw(List<Library> libraries) async {
  final fixed = moveFontsToRaw({
    for (final library in libraries)
      library.fileName: ZipDecoder().decodeBytes(library.bytes),
  });
  if (fixed.libraries.isEmpty) {
    return libraries;
  }
  for (final MapEntry(key: fileName, value: shim) in fixed.shims.entries) {
    await _addFontShim(fixed.libraries[fileName]!, shim);
  }
  _lgr.info('Moved fonts to res/raw so Kodular can build: '
      '${fixed.libraries.keys.join(', ')}');
  return [
    for (final library in libraries)
      if (fixed.libraries[library.fileName] case final archive?)
        Library(library.fileName, zipBytes(archive.files))
      else
        library,
  ];
}

Future<void> _addFontShim(Archive aar, FontShim shim) async {
  final dir = p.join(_fs.buildFilesDir.path, 'font-shims', shim.package);
  final source = p.join(dir, 'R.java').asFile(true);
  await source.writeAsString(shim.source);
  final classes = p.join(dir, 'classes');
  await Executor.execJavac(sources: {source.path}, output: classes);

  final shimEntry = '${shim.package.replaceAll('.', '/')}/R\$font.class';
  final classesJar = aar.findFile('classes.jar');
  aar.add(ArchiveFile.bytes(
      'classes.jar',
      zipBytes([
        if (classesJar != null)
          ...ZipDecoder().decodeBytes(classesJar.content).files,
        ArchiveFile.bytes(
            shimEntry, await p.join(classes, shimEntry).asFile().readAsBytes()),
      ])));
}

Future<Library> _packageAar(
    LibraryDesugarer desugarer, Artifact aar, BuildDependencies deps) async {
  final name = _aarFileName(aar);
  final desugaredClasses = await desugarer.desugar(
    name,
    input: aar.classesJar,
    classpathJars: {...deps.referencedJars, ...deps.privateJars}
      ..remove(aar.classesJar),
  );
  return Library(
      name,
      await BuildUtils.zipReplacingEntry(
        source: aar.artifactFile,
        entry: 'classes.jar',
        replacement: desugaredClasses,
      ));
}

Future<Map<Artifact, List<ArchiveFile>>> _sharedJarClasses(
    List<Artifact> jars) async {
  final classesByJar = {
    for (final jar in jars)
      jar: ZipDecoder()
          .decodeBytes(await jar.classesJar.asFile().readAsBytes())
          .files
          .where((el) => el.isFile && p.extension(el.name) == '.class')
          .toList(),
  };
  final assigned = assignSharedClasses({
    for (final MapEntry(key: jar, value: classes) in classesByJar.entries)
      jar: classes.map((el) => el.name).toList(),
  });
  return {
    for (final MapEntry(key: jar, value: names) in assigned.entries)
      jar: classesByJar[jar]!.where((el) => names.contains(el.name)).toList(),
  };
}

Future<Library> _packageSharedJar(Config config, LibraryDesugarer desugarer,
    Artifact jar, List<ArchiveFile> classes, BuildDependencies deps) async {
  final name = _aarFileName(jar);
  final sharedJarsDir = p.join(_fs.buildFilesDir.path, 'shared-jars');
  final classesJar = p.join(sharedJarsDir, '$name.jar');
  await writeZip(classesJar, classes);

  final desugaredJar = await desugarer.desugar(
    name,
    input: classesJar,
    classpathJars: {...deps.referencedJars, ...deps.privateJars}
      ..remove(jar.classesJar),
  );
  return Library(
      name,
      zipBytes([
        ArchiveFile.string(
            'AndroidManifest.xml', _sharedJarManifest(jar, config.minSdk)),
        ArchiveFile.bytes(
            'classes.jar', await desugaredJar.asFile().readAsBytes()),
      ]));
}

String _sharedJarManifest(Artifact jar, int minSdk) {
  final package = [...jar.groupId.split('.'), jar.artifactId]
      .map((el) => el.replaceAll(RegExp('[^A-Za-z0-9_.]'), '_'))
      .join('.');
  return '''
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="$package">
  <uses-sdk android:minSdkVersion="$minSdk"/>
</manifest>
''';
}

String _aarFileName(Artifact aar) => aar.isMavenArtifact
    ? '${aar.coordinate.replaceAll(':', '-')}.aar'
    : p.basename(aar.artifactFile);
