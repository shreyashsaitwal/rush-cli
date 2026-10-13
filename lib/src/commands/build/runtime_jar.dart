import 'dart:io' show File;

import 'package:archive/archive_io.dart';
import 'package:collection/collection.dart';
import 'package:get_it/get_it.dart';
import 'package:path/path.dart' as p;

import 'package:rush/src/commands/build/library_plan.dart';
import 'package:rush/src/commands/build/proguard_rules.dart';
import 'package:rush/src/commands/build/relocation.dart';
import 'package:rush/src/commands/build/resources.dart';
import 'package:rush/src/commands/build/tools/executor.dart';
import 'package:rush/src/config/config.dart';
import 'package:rush/src/services/file_service.dart';
import 'package:rush/src/services/lib_service.dart';
import 'package:rush/src/services/logger.dart';
import 'package:rush/src/utils/file_extension.dart';
import 'package:rush/src/utils/zip.dart';

const _coreLibraryMinSdk = 24;

final _fs = GetIt.I<FileService>();
final _lgr = GetIt.I<Logger>();
final _libService = GetIt.I<LibService>();

Future<String> createArtJar(Set<String> requiredJars) async {
  final artJarPath =
      p.join(_fs.buildRawDir.path, 'files', 'AndroidRuntime.jar');
  final entries = <ArchiveFile>[];

  // Add class files from all required deps into the ART.jar
  if (requiredJars.isNotEmpty) {
    _lgr.info('Merging dependencies into a single JAR...');

    final addedPaths = <String>{};
    for (final jarPath in requiredJars) {
      final jar = jarPath.asFile();
      if (!await jar.exists()) {
        throw Exception('Unable to find required JAR: $jarPath');
      }

      final decodedJar = ZipDecoder()
          .decodeBytes(await jar.readAsBytes())
          .files
          .whereNot((el) =>
              addedPaths.contains(el.name) || el.name.startsWith('META-INF'))
          // Do not include files other than .class files.
          .where((el) {
        if (!el.isFile) {
          return true;
        }
        return p.extension(el.name) == '.class';
      });
      for (final file in decodedJar) {
        entries.add(file..compression = CompressionType.none);
        addedPaths.add(file.name);
      }
    }
  }

  // Add extension classes to ART.jar
  final classFiles = _fs.buildClassesDir.listSync(recursive: true);
  for (final file in classFiles) {
    if (file is File &&
        !file.path.contains('META-INF') &&
        p.extension(file.path) == '.class') {
      entries.add(await fileEntry(file, from: _fs.buildClassesDir.path));
    }
  }

  await writeZip(artJarPath, entries);
  return artJarPath;
}

Future<void> runProGuard(Config config, String artJarPath, LibraryPlan plan,
    ExtensionResources? resources,
    {required bool optimize}) async {
  final projectRules = p.join(_fs.srcDir.path, 'proguard-rules.pro').asFile();
  await Executor.execProGuard(
    config,
    artJarPath,
    {...plan.libraryJars, if (resources != null) resources.classesDir},
    {
      ...plan.consumerRules,
      ...await _bundledProguardRules(plan.privateJars),
      if (!optimize) await _keepExtensionClassesRules(),
      if (await projectRules.exists()) projectRules.path,
    },
    shrinkOnly: !optimize,
  );
}

Future<List<String>> _bundledProguardRules(Set<String> jars) async {
  final rulesDir = p.join(_fs.buildFilesDir.path, 'bundled-proguard-rules');
  final rules = <String>[];
  for (final jar in jars) {
    final entries = ZipDecoder()
        .decodeBytes(await jar.asFile().readAsBytes())
        .files
        .where((el) =>
            el.isFile &&
            el.name.startsWith('META-INF/proguard/') &&
            p.extension(el.name) == '.pro');
    for (final entry in entries) {
      final file = p
          .join(
              rulesDir, p.basenameWithoutExtension(jar), p.basename(entry.name))
          .asFile(true);
      await file.writeAsBytes(entry.content);
      rules.add(file.path);
    }
  }
  return rules;
}

Future<String> _keepExtensionClassesRules() async {
  final classesDir = _fs.buildClassesDir.path;
  final classFiles = _fs.buildClassesDir
      .listSync(recursive: true)
      .whereType<File>()
      .map((el) =>
          p.posix.joinAll(p.split(p.relative(el.path, from: classesDir))));
  final rules =
      p.join(_fs.buildFilesDir.path, 'keep-extension-classes.pro').asFile();
  await rules.writeAsString(keepClassesRules(classFiles));
  return rules.path;
}

Future<void> relocatePrivateClasses(
    String artJarPath, Set<String> privateJars, String package) async {
  final classes = {
    for (final jar in privateJars)
      ...relocatableClasses(await _fileEntries(jar)),
  };
  _lgr.info('Moved ${privateJars.length} bundled libraries to '
      '${await _relocate(artJarPath, classes, package)}');
}

Future<void> _relocateDesugarHelpers(String artJarPath, String package) async {
  final helpers = desugarHelpers(await _fileEntries(artJarPath));
  if (helpers.isNotEmpty) {
    await _relocate(artJarPath, helpers, package);
  }
}

Future<Iterable<String>> _fileEntries(String jar) async => ZipDecoder()
    .decodeBytes(await jar.asFile().readAsBytes())
    .files
    .where((el) => el.isFile)
    .map((el) => el.name);

Future<String> _relocate(
    String artJarPath, Iterable<String> classes, String package) async {
  final classList =
      p.join(_fs.buildFilesDir.path, 'relocated-classes.txt').asFile();
  await classList.writeAsString(classes.join('\n'));

  final repackaged = '$package.repacked';
  final relocated =
      p.join(_fs.buildFilesDir.path, 'AndroidRuntime.relocated.jar');
  await Executor.execRelocator(
    input: artJarPath,
    output: relocated,
    prefix: '${repackaged.replaceAll('.', '/')}/',
    classList: classList.path,
  );
  await relocated.asFile().rename(artJarPath);
  return repackaged;
}

Future<void> desugarArtJar(
    Config config, String artJarPath, LibraryPlan plan, String package) async {
  final coreLibraryConfig = config.minSdk >= _coreLibraryMinSdk
      ? await _extractCoreLibraryConfig()
      : null;
  final desugared =
      p.join(_fs.buildFilesDir.path, 'AndroidRuntime.desugared.jar');
  await Executor.execDesugar(
    config,
    input: artJarPath,
    output: desugared,
    classpathJars: plan.libraryJars,
    coreLibraryConfig: coreLibraryConfig,
  );
  await desugared.asFile().rename(artJarPath);
  if (coreLibraryConfig != null) {
    await _addCoreLibrary(config.minSdk, coreLibraryConfig, artJarPath);
  }
  await _relocateDesugarHelpers(artJarPath, package);
}

Future<String> _extractCoreLibraryConfig() async {
  final configJar = ZipDecoder().decodeBytes(
      await (await _libService.coreLibraryConfigJar()).asFile().readAsBytes());
  final config = p.join(_fs.buildFilesDir.path, 'core-library.json').asFile();
  await config.writeAsBytes(
      configJar.findFile('META-INF/desugar/d8/desugar.json')!.content);
  return config.path;
}

Future<void> _addCoreLibrary(
    int minSdk, String coreLibraryConfig, String artJarPath) async {
  final version = coreLibraryCoord.split(':').last;
  final library =
      p.join(_fs.buildFilesDir.path, 'core-library-$version-api$minSdk.jar');
  if (!await library.asFile().exists()) {
    await Executor.execL8(
        minSdk: minSdk, coreLibraryConfig: coreLibraryConfig, output: library);
  }

  final keepRules =
      p.join(_fs.buildFilesDir.path, 'core-library-keep.pro').asFile();
  await Executor.execTraceReferences(
    source: artJarPath,
    target: library,
    output: keepRules.path,
  );
  if ((await keepRules.readAsString()).trim().isEmpty) {
    return;
  }

  final shrinkOnlyRules =
      p.join(_fs.buildFilesDir.path, 'shrink-only.pro').asFile();
  await shrinkOnlyRules
      .writeAsString('-dontobfuscate\n-dontoptimize\n-keepattributes *\n');
  final shrunk = p.join(_fs.buildFilesDir.path, 'core-library.jar');
  await Executor.execR8Shrink(
    input: library,
    rules: {keepRules.path, shrinkOnlyRules.path},
    output: shrunk,
  );
  await _appendClasses(artJarPath, shrunk);
}

Future<void> _appendClasses(String jarPath, String classesJarPath) async {
  final jar = ZipDecoder().decodeBytes(await jarPath.asFile().readAsBytes());
  final classes =
      ZipDecoder().decodeBytes(await classesJarPath.asFile().readAsBytes());
  await writeZip(jarPath, [
    ...jar.files,
    ...classes.files
        .where((el) => el.isFile && !el.name.startsWith('META-INF/')),
  ]);
}
