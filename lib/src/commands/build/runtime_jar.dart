import 'dart:io' show File, ProcessException;

import 'package:archive/archive_io.dart';
import 'package:collection/collection.dart';
import 'package:get_it/get_it.dart';
import 'package:path/path.dart' as p;
import 'package:tint/tint.dart';

import 'package:rush/src/commands/build/library_plan.dart';
import 'package:rush/src/commands/build/private_libraries.dart';
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
              addedPaths.contains(el.name) ||
              el.name.startsWith('META-INF') ||
              el.name == 'module-info.class')
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

final _repackageRule = RegExp(r'^\s*-repackageclasses\b', multiLine: true);

File get _projectRules =>
    p.join(_fs.srcDir.path, 'proguard-rules.pro').asFile();

Future<void> checkProjectRules() async {
  if (await _projectRules.exists() &&
      _repackageRule.hasMatch(await _projectRules.readAsString())) {
    throw Exception('src/proguard-rules.pro sets -repackageclasses, which Rush '
        'applies itself to optimized builds. Remove it, or run `rush migrate`.');
  }
}

Future<void> shrinkRuntimeJar(String artJarPath, LibraryPlan plan,
    ExtensionResources? resources, String package,
    {required bool optimize,
    required Iterable<String> privateAarClasses}) async {
  final projectRules = _projectRules;
  final mapping = _mapping(package);
  try {
    await Executor.execR8(
      artJarPath,
      libraryJars: {
        ...plan.libraryJars,
        ...privateAarClasses,
        if (resources != null) resources.classesJar,
      },
      rules: {
        ...plan.consumerRules,
        ...await _bundledProguardRules(plan.privateJars),
        if (!optimize) ...await _shrinkOnlyRules(),
        if (optimize) await _repackageRules(package),
        if (privateAarClasses.isNotEmpty)
          await _keptForPrivateAars(artJarPath, privateAarClasses),
        if (await projectRules.exists()) projectRules.path,
      },
      mapping: optimize ? mapping.path : null,
    );
  } on ProcessException {
    _lgr.log(
        'If R8 reports missing classes, add the library that provides them '
        'to `dependencies`, or, if that code never runs, add -dontwarn rules '
        'for them to src/proguard-rules.pro',
        'help  '.green());
    rethrow;
  }
  if (optimize) {
    _lgr.info('Wrote the mapping of renamed classes to '
        '${p.relative(mapping.path, from: _fs.cwd)}');
  }
}

Future<String> _keptForPrivateAars(
    String artJarPath, Iterable<String> privateAarClasses) async {
  final rules = p.join(_fs.buildFilesDir.path, 'private-aar-keep.pro');
  await Executor.execTraceReferences(
      sources: privateAarClasses, target: artJarPath, output: rules);
  return rules;
}

File _mapping(String package) =>
    p.join(_fs.cwd, 'out', '$package.mapping.txt').asFile();

Future<void> removeMapping(String package) async {
  final mapping = _mapping(package);
  if (await mapping.exists()) {
    await mapping.delete();
  }
}

Future<List<String>> _shrinkOnlyRules() async {
  final rules = p.join(_fs.buildFilesDir.path, 'shrink-only.pro').asFile();
  await rules.writeAsString('-dontobfuscate\n-dontoptimize\n-keepattributes *\n'
      '-keep class kotlin.Metadata { *; }\n-processkotlinnullchecks keep\n');
  return [rules.path, await _keepExtensionClassesRules()];
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

Future<String> _repackageRules(String package) async {
  final rules = p.join(_fs.buildFilesDir.path, 'repackage.pro').asFile();
  await rules.writeAsString('-repackageclasses $package.repacked\n');
  return rules.path;
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
    String artJarPath, PrivateLibraries privateLibraries) async {
  final relocated =
      p.join(_fs.buildFilesDir.path, 'AndroidRuntime.relocated.jar');
  await privateLibraries.relocate(artJarPath, relocated);
  await relocated.asFile().rename(artJarPath);
  _lgr.info('Moved private libraries to '
      '${privateLibraries.names.package}.repacked');
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

Future<void> _relocate(
    String artJarPath, Iterable<String> classes, String package) async {
  final spec =
      p.join(_fs.buildFilesDir.path, 'desugar-helpers-relocation.txt').asFile();
  await spec.writeAsString(
      relocationSpec('${package.replaceAll('.', '/')}/repacked/', classes));

  final relocated =
      p.join(_fs.buildFilesDir.path, 'AndroidRuntime.relocated.jar');
  await Executor.execRelocator(
      input: artJarPath, output: relocated, spec: spec.path);
  await relocated.asFile().rename(artJarPath);
}

Future<void> desugarArtJar(Config config, String artJarPath, LibraryPlan plan,
    String package, Iterable<String> privateAarClasses) async {
  final coreLibraryConfig = config.minSdk >= _coreLibraryMinSdk
      ? await _extractCoreLibraryConfig()
      : null;
  final desugared =
      p.join(_fs.buildFilesDir.path, 'AndroidRuntime.desugared.jar');
  await Executor.execDesugar(
    config,
    input: artJarPath,
    output: desugared,
    classpathJars: {...plan.libraryJars, ...privateAarClasses},
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
    sources: [artJarPath],
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
