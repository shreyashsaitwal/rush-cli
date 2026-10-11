import 'dart:convert' show jsonDecode, jsonEncode;
import 'dart:io' show File, Platform, ProcessException;

import 'package:archive/archive_io.dart';
import 'package:args/command_runner.dart';
import 'package:collection/collection.dart';
import 'package:get_it/get_it.dart';
import 'package:hive/hive.dart';
import 'package:path/path.dart' as p;
import 'package:pool/pool.dart';
import 'package:tint/tint.dart';

import 'package:rush/src/commands/build/build_dependencies.dart';
import 'package:rush/src/commands/build/utils.dart';
import 'package:rush/src/commands/deps/sync.dart';
import 'package:rush/src/commands/build/tools/compiler.dart';
import 'package:rush/src/commands/build/tools/executor.dart';
import 'package:rush/src/config/config.dart';
import 'package:rush/src/resolver/artifact.dart';
import 'package:rush/src/services/lib_service.dart';
import 'package:rush/src/services/file_service.dart';
import 'package:rush/src/services/logger.dart';
import 'package:rush/src/utils/constants.dart';
import 'package:rush/src/utils/file_extension.dart';

class BuildCommand extends Command<int> {
  final Logger _lgr = GetIt.I<Logger>();
  final FileService _fs = GetIt.I<FileService>();
  late final LibService _libService;

  BuildCommand() {
    argParser.addFlag(
      'optimize',
      abbr: 'o',
      help:
          'Optimizes, shrinks and obfuscates extension\'s code using ProGuard.',
    );
  }

  @override
  String get description =>
      'Builds the extension project in current working directory.';

  @override
  String get name => 'build';

  final _stopwatch = Stopwatch();

  /// Builds the extension in the current directory
  @override
  Future<int> run() async {
    _stopwatch.start();
    _lgr.startTask('Initializing build');

    await GetIt.I.isReady<LibService>();
    _libService = GetIt.I<LibService>();

    final config = await Config.require(_fs.configFile, _lgr);
    if (config == null) {
      _lgr.stopTask(false);
      _logFinalLine(false);
      return 1;
    }
    _lgr.stopTask();

    if (await SyncSubCommand.needsSync(config, _libService) &&
        await SyncSubCommand().run(title: 'Syncing dependencies') != 0) {
      _logFinalLine(false);
      return 1;
    }

    _lgr.startTask('Compiling sources');
    final BuildDependencies deps;
    try {
      deps = await BuildDependencies.load(_libService, config);
      final timestampBox = await Hive.openLazyBox<DateTime>(timestampBoxName);
      await _mergeManifests(config, deps.shippedAars);
      await _compile(config, timestampBox);
    } catch (e, s) {
      _catchAndStop(e, s);
      return 1;
    }
    _lgr.stopTask();

    _lgr.startTask('Processing');
    final componentsJson =
        p.join(_fs.buildRawDir.path, 'components.json').asFile();
    final buildInfosJson = p
        .join(_fs.buildRawDir.path, 'files', 'component_build_infos.json')
        .asFile();
    if (!await componentsJson.exists() || !await buildInfosJson.exists()) {
      _lgr
        ..err('Unable to find components.json or component_build_infos.json')
        ..log(
            '${'help '.green()} Make sure you have annotated your extension with @Extension annotation')
        ..stopTask(false);
      return 1;
    }

    final String artJarPath;
    try {
      await BuildUtils.copyAssets(config);
      await BuildUtils.copyLicense(config);
      await _packageAars(config, deps, buildInfosJson);
      artJarPath = await _createArtJar(deps.privateJars);
    } catch (e, s) {
      _catchAndStop(e, s);
      return 1;
    }
    _lgr.stopTask();

    final optimize = argResults!['optimize'] as bool;
    if (optimize || deps.privateJars.isNotEmpty) {
      _lgr.startTask(optimize
          ? 'Optimizing and obfuscating the bytecode'
          : 'Shrinking bundled libraries');
      try {
        await _runProGuard(config, artJarPath, deps, optimize: optimize);
      } catch (e, s) {
        _catchAndStop(e, s);
        return 1;
      }
      _lgr.stopTask();
    }

    if (deps.privateJars.isNotEmpty) {
      _lgr.startTask('Relocating bundled libraries');
      try {
        await _relocatePrivateClasses(artJarPath, deps.privateJars);
      } catch (e, s) {
        _catchAndStop(e, s);
        return 1;
      }
      _lgr.stopTask();
    }

    _lgr.startTask('Desugaring Java 8+ language features');
    try {
      await _desugarArtJar(config, artJarPath, deps);
    } catch (e, s) {
      _catchAndStop(e, s);
      return 1;
    }
    _lgr.stopTask();

    _lgr.startTask('Generating DEX bytecode');
    try {
      await Executor.execD8(config, artJarPath, deps.referencedJars);
    } catch (e, s) {
      _catchAndStop(e, s);
      return 1;
    }
    _lgr.stopTask();

    _lgr.startTask('Packaging the extension');
    try {
      await _assemble();
    } catch (e, s) {
      _catchAndStop(e, s);
      return 1;
    }
    _lgr.stopTask();

    _logFinalLine(true);
    return 0;
  }

  void _catchAndStop(Object e, StackTrace s) {
    if (e is ProcessException) {
      _lgr.dbg(e.toString());
    } else if (e.toString().isNotEmpty) {
      _lgr.err(e.toString());
    }
    _lgr
      ..dbg(s.toString())
      ..stopTask(false);

    _logFinalLine(false);
  }

  void _logFinalLine(bool success) {
    var line = '\n';
    line += success ? '• '.green() : '• '.red();
    line += success ? 'BUILD SUCCESSFUL ' : 'BUILD FAILED ';

    final time = (_stopwatch.elapsedMilliseconds / 1000).toStringAsFixed(2);
    line += '(took ${time}s)'.grey();
    _lgr.log(line);
  }

  Future<void> _mergeManifests(Config config, List<Artifact> aars) async {
    final manifests = aars
        .map((el) => _fs.resourceFromExtractedAar(
            el.artifactFile, 'AndroidManifest.xml'))
        .where((el) => el.existsSync())
        .map((el) => el.path);

    final mainManifest =
        p.join(_fs.srcDir.path, 'AndroidManifest.xml').asFile();
    final outputManifest =
        p.join(_fs.buildFilesDir.path, 'AndroidManifest.xml').asFile(true);

    if (manifests.isEmpty) {
      _lgr.dbg('No manifests found in dependencies; skipping manifest merge');
      await outputManifest.delete();
      return;
    }

    _lgr.info('Merging Android manifests...');
    await Executor.execManifMerger(
      config.minSdk,
      mainManifest.path,
      manifests.toSet(),
    );
  }

  /// Compiles extension's source files.
  Future<void> _compile(Config config, LazyBox<DateTime> timestampBox) async {
    final srcFiles =
        _fs.srcDir.path.asDir().listSync(recursive: true).whereType<File>();
    final javaFiles = srcFiles
        .whereType<File>()
        .where((file) => p.extension(file.path) == '.java');
    final ktFiles = srcFiles
        .whereType<File>()
        .where((file) => p.extension(file.path) == '.kt');

    final fileCount = javaFiles.length + ktFiles.length;
    _lgr.info('Picked $fileCount source file${fileCount > 1 ? 's' : ''}');

    final dependencies = await _libService.extensionDependencies(config,
        includeAi2ProvidedDeps: true, includeProjectProvidedDeps: true);
    final compileClasspathJars = dependencies
        .where((el) => el.scope == Scope.compile || el.scope == Scope.provided)
        .map((el) => el.classpathJars(dependencies))
        .flattened
        .toSet();

    await Compiler.compile(
      compileClasspathJars,
      javaFiles: javaFiles.map((file) => file.path).toSet(),
      kotlinFiles: ktFiles.map((file) => file.path).toSet(),
      kotlinVersion: config.kotlin.compilerVersion,
      timestampBox: timestampBox,
    );
  }

  Future<void> _packageAars(
      Config config, BuildDependencies deps, File buildInfosJson) async {
    final aarsDir = p.join(_fs.buildRawDir.path, 'aars').asDir();
    if (await aarsDir.exists()) {
      await aarsDir.delete(recursive: true);
    }
    await aarsDir.create();

    final pool = Pool(Platform.numberOfProcessors.clamp(1, 4));
    final sharedClasses = await _sharedJarClasses(deps.sharedJars);
    final libraries = await Future.wait([
      ...deps.shippedAars.map((aar) => pool
          .withResource(() => _packageAar(config, aar, aarsDir.path, deps))),
      ...sharedClasses.entries.map((el) => pool.withResource(() =>
          _packageSharedJar(config, el.key, el.value, aarsDir.path, deps))),
    ]);

    final buildInfos = jsonDecode(await buildInfosJson.readAsString()) as List;
    for (final info in buildInfos.cast<Map<String, dynamic>>()) {
      info['libraries'] = libraries;
    }
    await buildInfosJson.writeAsString(jsonEncode(buildInfos));

    if (libraries.isNotEmpty) {
      _lgr.info('Packaged ${libraries.length} AAR(s): ${libraries.join(', ')}');
    }
  }

  Future<String> _packageAar(Config config, Artifact aar, String aarsDir,
      BuildDependencies deps) async {
    final name = _aarFileName(aar);
    final desugaredClasses =
        p.join(_fs.buildFilesDir.path, 'desugared-aars', '$name.jar');
    p.dirname(desugaredClasses).asDir(true);

    await Executor.execDesugar(
      config,
      input: aar.classesJar,
      output: desugaredClasses,
      classpathJars: {...deps.referencedJars, ...deps.privateJars}
        ..remove(aar.classesJar),
    );
    await BuildUtils.copyZipReplacingEntry(
      source: aar.artifactFile,
      entry: 'classes.jar',
      replacement: desugaredClasses,
      destination: p.join(aarsDir, name),
    );
    return name;
  }

  static Future<Map<Artifact, Archive>> _sharedJarClasses(
      List<Artifact> jars) async {
    final classesByJar = {
      for (final jar in jars)
        jar: ZipDecoder()
            .decodeBytes(await jar.classesJar.asFile().readAsBytes())
            .files
            .where((el) => el.isFile && p.extension(el.name) == '.class')
            .toList(),
    };
    final packagedClasses = <String>{};
    final result = <Artifact, Archive>{};
    for (final jar in jars.sortedBy<num>((el) => -classesByJar[el]!.length)) {
      final classes = classesByJar[jar]!
          .where((el) => packagedClasses.add(el.name))
          .toList();
      if (classes.isNotEmpty) {
        result[jar] = Archive();
        classes.forEach(result[jar]!.add);
      }
    }
    return result;
  }

  Future<String> _packageSharedJar(Config config, Artifact jar, Archive classes,
      String aarsDir, BuildDependencies deps) async {
    final name = _aarFileName(jar);
    final sharedJarsDir = p.join(_fs.buildFilesDir.path, 'shared-jars');
    final classesJar = p.join(sharedJarsDir, '$name.jar');
    final desugaredJar = p.join(sharedJarsDir, '$name.desugared.jar');
    await classesJar
        .asFile(true)
        .writeAsBytes(ZipEncoder().encodeBytes(classes));

    await Executor.execDesugar(
      config,
      input: classesJar,
      output: desugaredJar,
      classpathJars: {...deps.referencedJars, ...deps.privateJars}
        ..remove(jar.classesJar),
    );
    final aar = Archive()
      ..add(ArchiveFile.string(
          'AndroidManifest.xml', _sharedJarManifest(jar, config.minSdk)))
      ..add(ArchiveFile.bytes(
          'classes.jar', await desugaredJar.asFile().readAsBytes()));
    await p
        .join(aarsDir, name)
        .asFile(true)
        .writeAsBytes(ZipEncoder().encodeBytes(aar));
    return name;
  }

  static String _sharedJarManifest(Artifact jar, int minSdk) {
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

  Future<void> _runProGuard(
      Config config, String artJarPath, BuildDependencies deps,
      {required bool optimize}) async {
    final allDeps = await _libService.extensionDependencies(config,
        includeAi2ProvidedDeps: true, includeProjectProvidedDeps: true);
    final aarRules = allDeps
        .where((el) => el.packaging == 'aar')
        .map((el) =>
            _fs.resourceFromExtractedAar(el.artifactFile, 'proguard.txt'))
        .where((el) => el.existsSync())
        .map((el) => el.path);

    await Executor.execProGuard(
      config,
      artJarPath,
      deps.referencedJars,
      {
        ...aarRules,
        ...await _bundledProguardRules(deps.privateJars),
        if (!optimize) await _keepExtensionClassesRules(),
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
            .join(rulesDir, p.basenameWithoutExtension(jar),
                p.basename(entry.name))
            .asFile(true);
        await file.writeAsBytes(entry.content);
        rules.add(file.path);
      }
    }
    return rules;
  }

  Future<String> _keepExtensionClassesRules() async {
    final classesDir = _fs.buildClassesDir.path;
    final classNames = _fs.buildClassesDir
        .listSync(recursive: true)
        .whereType<File>()
        .where((el) => p.extension(el.path) == '.class')
        .map((el) =>
            p.split(p.withoutExtension(p.relative(el.path, from: classesDir))))
        .where((el) => el.first != 'META-INF')
        .map((el) => el.join('.'));
    final rules =
        p.join(_fs.buildFilesDir.path, 'keep-extension-classes.pro').asFile();
    await rules.writeAsString(
        classNames.map((el) => '-keep class $el { *; }').join('\n'));
    return rules.path;
  }

  Future<void> _relocatePrivateClasses(
      String artJarPath, Set<String> privateJars) async {
    final classes = {
      for (final jar in privateJars)
        ...ZipDecoder()
            .decodeBytes(await jar.asFile().readAsBytes())
            .files
            .where((el) =>
                el.isFile &&
                !el.name.startsWith('META-INF') &&
                p.extension(el.name) == '.class')
            .map((el) => p.withoutExtension(el.name)),
    };
    final classList =
        p.join(_fs.buildFilesDir.path, 'relocated-classes.txt').asFile();
    await classList.writeAsString(classes.join('\n'));

    final package = '${await _extensionPackage()}.repacked';
    final relocated =
        p.join(_fs.buildFilesDir.path, 'AndroidRuntime.relocated.jar');
    await Executor.execRelocator(
      input: artJarPath,
      output: relocated,
      prefix: '${package.replaceAll('.', '/')}/',
      classList: classList.path,
    );
    await relocated.asFile().rename(artJarPath);
    _lgr.info('Moved ${privateJars.length} bundled libraries to $package');
  }

  Future<void> _desugarArtJar(
      Config config, String artJarPath, BuildDependencies deps) async {
    final desugared =
        p.join(_fs.buildFilesDir.path, 'AndroidRuntime.desugared.jar');
    await Executor.execDesugar(
      config,
      input: artJarPath,
      output: desugared,
      classpathJars: deps.referencedJars,
    );
    await desugared.asFile().rename(artJarPath);
  }

  static String _aarFileName(Artifact aar) => aar.isMavenArtifact
      ? '${aar.coordinate.replaceAll(':', '-')}.aar'
      : p.basename(aar.artifactFile);

  Future<String> _createArtJar(Set<String> requiredJars) async {
    final artJarPath =
        p.join(_fs.buildRawDir.path, 'files', 'AndroidRuntime.jar');
    final zipEncoder = ZipFileEncoder()..create(artJarPath);

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
          zipEncoder.addArchiveFile(file..compression = CompressionType.none);
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
        final path = p.relative(file.path, from: _fs.buildClassesDir.path);
        await zipEncoder.addFile(file, path);
      }
    }

    await zipEncoder.close();
    return artJarPath;
  }

  Future<String> _extensionPackage() async {
    final componentsJsonFile =
        p.join(_fs.buildDir.path, 'raw', 'components.json').asFile();

    final json = jsonDecode(await componentsJsonFile.readAsString());
    final type = json[0]['type'] as String;

    final split = type.split('.')..removeLast();
    return split.join('.');
  }

  Future<void> _assemble() async {
    final org = await _extensionPackage();

    final outputDir = p.join(_fs.cwd, 'out').asDir(true);
    final aix = p.join(outputDir.path, '$org.aix');
    final zipEncoder = ZipFileEncoder()..create(aix);

    try {
      for (final file in _fs.buildRawDir.listSync(recursive: true)) {
        if (file is File) {
          final name = p.relative(file.path, from: _fs.buildRawDir.path);
          await zipEncoder.addFile(file, p.join(org, name));
        }
      }
      _lgr.info('Generated AIX file at ${aix.blue()}');
    } catch (e) {
      rethrow;
    } finally {
      await zipEncoder.close();
    }
  }
}
