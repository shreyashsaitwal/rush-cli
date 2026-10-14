import 'dart:io' show Platform;

import 'package:archive/archive_io.dart';
import 'package:get_it/get_it.dart';
import 'package:path/path.dart' as p;
import 'package:pool/pool.dart';

import 'package:rush/src/commands/build/aix.dart';
import 'package:rush/src/commands/build/fixes/id_resources.dart';
import 'package:rush/src/commands/build/fixes/raw_fonts.dart';
import 'package:rush/src/commands/build/libraries.dart';
import 'package:rush/src/commands/build/library_plan.dart';
import 'package:rush/src/commands/build/resources.dart';
import 'package:rush/src/commands/build/tools/executor.dart';
import 'package:rush/src/commands/build/tools/library_desugarer.dart';
import 'package:rush/src/commands/build/utils.dart';
import 'package:rush/src/config/config.dart';
import 'package:rush/src/services/file_service.dart';
import 'package:rush/src/services/logger.dart';
import 'package:rush/src/utils/file_extension.dart';
import 'package:rush/src/utils/zip.dart';

final _fs = GetIt.I<FileService>();
final _lgr = GetIt.I<Logger>();

Future<List<Library>> packageLibraries(
    Config config, LibraryPlan plan, ExtensionResources? resources) async {
  final pool = Pool(Platform.numberOfProcessors.clamp(1, 4));
  final sharedClasses = await _sharedJarClasses(plan.sharedJars);
  final desugarer = LibraryDesugarer(config);
  final libraries = await Future.wait([
    ...plan.sharedAars.map(
        (aar) => pool.withResource(() => _packageAar(desugarer, aar, plan))),
    ...sharedClasses.entries.map((el) => pool.withResource(
        () => _packageSharedJar(config, desugarer, el.key, el.value, plan))),
    if (resources != null) resources.packageAar(),
  ]);

  if (libraries.isNotEmpty) {
    _lgr.info('Packaged ${libraries.length} AAR(s): '
        '${libraries.map((el) => el.fileName).join(', ')}');
  }
  return libraries;
}

Future<List<Library>> moveLibraryFontsToRaw(List<Library> libraries) async {
  final fixed = moveFontsToRaw(_archives(libraries));
  if (fixed.libraries.isEmpty) {
    return libraries;
  }
  for (final MapEntry(key: fileName, value: shim) in fixed.shims.entries) {
    await _addFontShim(fixed.libraries[fileName]!, shim);
  }
  _lgr.info('Moved fonts to res/raw so Kodular can build: '
      '${fixed.libraries.keys.join(', ')}');
  return _replaced(libraries, fixed.libraries);
}

List<Library> writeLongIdResources(List<Library> libraries) {
  final fixed = withLongIdResources(_archives(libraries));
  if (fixed.isEmpty) {
    return libraries;
  }
  _lgr.info('Wrote id resources in the long form App Inventor\'s aapt '
      'accepts: ${fixed.keys.join(', ')}');
  return _replaced(libraries, fixed);
}

Map<String, Archive> _archives(List<Library> libraries) => {
      for (final library in libraries)
        library.fileName: ZipDecoder().decodeBytes(library.bytes),
    };

List<Library> _replaced(List<Library> libraries, Map<String, Archive> fixed) =>
    [
      for (final library in libraries)
        if (fixed[library.fileName] case final archive?)
          Library(library.fileName, zipBytes(archive.files))
        else
          library,
    ];

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
    LibraryDesugarer desugarer, ResolvedLibrary aar, LibraryPlan plan) async {
  final name = _aarFileName(aar);
  final desugaredClasses = await desugarer.desugar(
    name,
    input: aar.classesJar,
    classpathJars: {...plan.libraryJars, ...plan.privateJars}
      ..remove(aar.classesJar),
  );
  return Library(
      name,
      await BuildUtils.zipReplacingEntry(
        source: aar.file,
        entry: 'classes.jar',
        replacement: desugaredClasses,
      ));
}

Future<Map<ResolvedLibrary, List<ArchiveFile>>> _sharedJarClasses(
    Iterable<ResolvedLibrary> jars) async {
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
    ResolvedLibrary jar, List<ArchiveFile> classes, LibraryPlan plan) async {
  final name = _aarFileName(jar);
  final sharedJarsDir = p.join(_fs.buildFilesDir.path, 'shared-jars');
  final classesJar = p.join(sharedJarsDir, '$name.jar');
  await writeZip(classesJar, classes);

  final desugaredJar = await desugarer.desugar(
    name,
    input: classesJar,
    classpathJars: {...plan.libraryJars, ...plan.privateJars}
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

String _sharedJarManifest(ResolvedLibrary jar, int minSdk) {
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

String _aarFileName(ResolvedLibrary aar) => aar.isMavenArtifact
    ? '${aar.coordinate.replaceAll(':', '-')}.aar'
    : p.basename(aar.file);
