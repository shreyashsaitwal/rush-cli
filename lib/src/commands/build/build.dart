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

import 'package:rush/src/commands/build/aix.dart';
import 'package:rush/src/commands/build/build_dependencies.dart';
import 'package:rush/src/commands/build/docs.dart';
import 'package:rush/src/commands/build/resources.dart';
import 'package:rush/src/commands/build/utils.dart';
import 'package:rush/src/commands/deps/sync.dart';
import 'package:rush/src/commands/build/tools/compiler.dart';
import 'package:rush/src/commands/build/tools/executor.dart';
import 'package:rush/src/commands/build/tools/library_desugarer.dart';
import 'package:rush/src/config/config.dart';
import 'package:rush/src/resolver/artifact.dart';
import 'package:rush/src/services/lib_service.dart';
import 'package:rush/src/services/file_service.dart';
import 'package:rush/src/services/logger.dart';
import 'package:rush/src/utils/constants.dart';
import 'package:rush/src/utils/file_extension.dart';
import 'package:rush/src/utils/error_message.dart';
import 'package:rush/src/utils/zip.dart';

const _coreLibraryMinSdk = 24;

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
    try {
      await _build(optimize: argResults!['optimize'] as bool);
    } on _BuildFailed {
      _logFinalLine(false);
      return 1;
    }
    _logFinalLine(true);
    return 0;
  }

  Future<void> _build({required bool optimize}) async {
    final config = await _task('Initializing build', _loadConfig);

    if (await SyncSubCommand.needsSync(config, _libService) &&
        await SyncSubCommand().run(title: 'Syncing dependencies') != 0) {
      throw const _BuildFailed();
    }

    final (deps, resources) = await _task('Compiling sources', () async {
      final deps = await BuildDependencies.load(_libService, config);
      final timestampBox = await Hive.openLazyBox<DateTime>(timestampBoxName);
      await _mergeManifests(config, deps.shippedAars);
      await _warnAboutDuplicateAars(deps.shippedAars);
      final resources = await ExtensionResources.compile(config);
      await _compile(config, timestampBox, resources);
      return (deps, resources);
    });

    final artJarPath = await _task('Processing', () async {
      final buildInfosJson = await _requireExtension();
      await BuildUtils.copyAssets(config);
      await BuildUtils.copyLicense(config);
      await _packageAars(config, deps, buildInfosJson, resources);
      return _createArtJar(deps.privateJars);
    });

    if (optimize || deps.privateJars.isNotEmpty) {
      await _task(
          optimize
              ? 'Optimizing and obfuscating the bytecode'
              : 'Shrinking bundled libraries',
          () => _runProGuard(config, artJarPath, deps, resources,
              optimize: optimize));
    }

    if (deps.privateJars.isNotEmpty) {
      await _task('Relocating bundled libraries',
          () => _relocatePrivateClasses(artJarPath, deps.privateJars));
    }

    await _task('Desugaring Java 8+ language features',
        () => _desugarArtJar(config, artJarPath, deps));
    await _task('Generating DEX bytecode',
        () => Executor.execD8(config, artJarPath, deps.referencedJars));
    await _task('Packaging the extension', _assemble);
  }

  Future<T> _task<T>(String title, Future<T> Function() body) async {
    _lgr.startTask(title);
    try {
      final result = await body();
      _lgr.stopTask();
      return result;
    } catch (e, s) {
      _reportFailure(e, s);
      throw const _BuildFailed();
    }
  }

  Future<Config> _loadConfig() async {
    await GetIt.I.isReady<LibService>();
    _libService = GetIt.I<LibService>();

    final config = await Config.require(_fs.configFile, _lgr);
    if (config == null) {
      throw Exception();
    }
    for (final key in config.ignoredKeys) {
      _lgr.warn('`$key` in rush.yml has no effect. Remove it.');
    }
    final missingFiles = _missingFiles(config);
    for (final path in missingFiles) {
      _lgr.err('$path is listed in rush.yml but doesn\'t exist');
    }
    if (missingFiles.isNotEmpty) {
      throw Exception();
    }
    return config;
  }

  Future<File> _requireExtension() async {
    final componentsJson =
        p.join(_fs.buildRawDir.path, 'components.json').asFile();
    final buildInfosJson = p
        .join(_fs.buildRawDir.path, 'files', 'component_build_infos.json')
        .asFile();
    if (!await componentsJson.exists() ||
        !await buildInfosJson.exists() ||
        (jsonDecode(await componentsJson.readAsString()) as List).isEmpty) {
      _lgr
        ..err('No extension found')
        ..log('Annotate the extension class with @Extension', 'help  '.green());
      throw Exception();
    }
    return buildInfosJson;
  }

  List<String> _missingFiles(Config config) => [
        for (final asset in config.assets) p.posix.join('assets', asset),
        for (final dependency in [
          ...config.dependencies,
          ...config.providedDependencies
        ])
          if (dependency.endsWith('.jar') || dependency.endsWith('.aar'))
            p.posix.join('deps', dependency),
      ].where((path) => !p.join(_fs.cwd, path).asFile().existsSync()).toList();

  void _reportFailure(Object e, StackTrace s) {
    final message = errorMessage(e);
    if (e is ProcessException) {
      _lgr.dbg(message);
    } else if (message.isNotEmpty && message != 'Exception') {
      _lgr.err(message);
    }
    _lgr
      ..dbg(s.toString())
      ..stopTask(false);
  }

  void _logFinalLine(bool success) {
    var line = '\n';
    line += success ? '• '.green() : '• '.red();
    line += success ? 'BUILD SUCCESSFUL ' : 'BUILD FAILED ';

    final time = (_stopwatch.elapsedMilliseconds / 1000).toStringAsFixed(2);
    line += '(took ${time}s)'.grey();
    _lgr.log(line);
  }

  Future<void> _warnAboutDuplicateAars(List<Artifact> aars) async {
    final packages = <Artifact, String>{};
    for (final aar in aars) {
      final package = await _aarPackage(aar);
      if (package != null) {
        packages[aar] = package;
      }
    }
    final copiesByPackage = groupBy(packages.keys, (aar) => packages[aar]!);
    for (final MapEntry(key: package, value: copies)
        in copiesByPackage.entries) {
      if (copies.length > 1) {
        _lgr.warn('${copies.join(' and ')} are the same library ($package). '
            'App Inventor includes only one of them in the app, so remove '
            'the others from rush.yml.');
      }
    }
  }

  Future<String?> _aarPackage(Artifact aar) async {
    final manifest =
        _fs.resourceFromExtractedAar(aar.artifactFile, 'AndroidManifest.xml');
    if (!await manifest.exists()) {
      return null;
    }
    final package = RegExp(r'<manifest[^>]*\spackage\s*=\s*"([^"]+)"')
        .firstMatch(await manifest.readAsString());
    return package?.group(1);
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
  Future<void> _compile(Config config, LazyBox<DateTime> timestampBox,
      ExtensionResources? resources) async {
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
    if (resources != null) {
      compileClasspathJars.add(resources.classesDir);
    }

    await p
        .join(_fs.buildDir.path, 'config.json')
        .asFile(true)
        .writeAsString(jsonEncode(config.toJson()));
    await Compiler.compile(
      compileClasspathJars,
      javaFiles: javaFiles.map((file) => file.path).toSet(),
      kotlinFiles: ktFiles.map((file) => file.path).toSet(),
      kotlinVersion: config.kotlin.compilerVersion,
      timestampBox: timestampBox,
    );
  }

  Future<void> _packageAars(Config config, BuildDependencies deps,
      File buildInfosJson, ExtensionResources? resources) async {
    final aarsDir = p.join(_fs.buildRawDir.path, 'aars').asDir();
    if (await aarsDir.exists()) {
      await aarsDir.delete(recursive: true);
    }
    await aarsDir.create();

    final pool = Pool(Platform.numberOfProcessors.clamp(1, 4));
    final sharedClasses = await _sharedJarClasses(deps.sharedJars);
    final desugarer = LibraryDesugarer(config);
    final libraries = await Future.wait([
      ...deps.shippedAars.map((aar) => pool
          .withResource(() => _packageAar(desugarer, aar, aarsDir.path, deps))),
      ...sharedClasses.entries.map((el) => pool.withResource(() =>
          _packageSharedJar(
              config, desugarer, el.key, el.value, aarsDir.path, deps))),
      if (resources != null) resources.packageAar(aarsDir.path),
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

  Future<String> _packageAar(LibraryDesugarer desugarer, Artifact aar,
      String aarsDir, BuildDependencies deps) async {
    final name = _aarFileName(aar);
    final desugaredClasses =
        p.join(_fs.buildFilesDir.path, 'desugared-aars', '$name.jar');
    p.dirname(desugaredClasses).asDir(true);

    await desugarer.desugar(
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

  Future<String> _packageSharedJar(
      Config config,
      LibraryDesugarer desugarer,
      Artifact jar,
      Archive classes,
      String aarsDir,
      BuildDependencies deps) async {
    final name = _aarFileName(jar);
    final sharedJarsDir = p.join(_fs.buildFilesDir.path, 'shared-jars');
    final classesJar = p.join(sharedJarsDir, '$name.jar');
    final desugaredJar = p.join(sharedJarsDir, '$name.desugared.jar');
    await writeZip(classesJar, classes.files);

    await desugarer.desugar(
      input: classesJar,
      output: desugaredJar,
      classpathJars: {...deps.referencedJars, ...deps.privateJars}
        ..remove(jar.classesJar),
    );
    await writeZip(p.join(aarsDir, name), [
      ArchiveFile.string(
          'AndroidManifest.xml', _sharedJarManifest(jar, config.minSdk)),
      ArchiveFile.bytes(
          'classes.jar', await desugaredJar.asFile().readAsBytes()),
    ]);
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

  Future<void> _runProGuard(Config config, String artJarPath,
      BuildDependencies deps, ExtensionResources? resources,
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
      {...deps.referencedJars, if (resources != null) resources.classesDir},
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
    final package = await _relocate(artJarPath, classes);
    _lgr.info('Moved ${privateJars.length} bundled libraries to $package');
  }

  Future<void> _relocateDesugarHelpers(String artJarPath) async {
    final helpers = ZipDecoder()
        .decodeBytes(await artJarPath.asFile().readAsBytes())
        .files
        .where((el) =>
            el.isFile &&
            (el.name.startsWith('com/android/tools/r8/') ||
                el.name.startsWith(r'j$/')) &&
            p.extension(el.name) == '.class')
        .map((el) => p.withoutExtension(el.name));
    if (helpers.isNotEmpty) {
      await _relocate(artJarPath, helpers);
    }
  }

  Future<String> _relocate(String artJarPath, Iterable<String> classes) async {
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
    return package;
  }

  Future<void> _desugarArtJar(
      Config config, String artJarPath, BuildDependencies deps) async {
    final coreLibraryConfig = config.minSdk >= _coreLibraryMinSdk
        ? await _extractCoreLibraryConfig()
        : null;
    final desugared =
        p.join(_fs.buildFilesDir.path, 'AndroidRuntime.desugared.jar');
    await Executor.execDesugar(
      config,
      input: artJarPath,
      output: desugared,
      classpathJars: deps.referencedJars,
      coreLibraryConfig: coreLibraryConfig,
    );
    await desugared.asFile().rename(artJarPath);
    if (coreLibraryConfig != null) {
      await _addCoreLibrary(config.minSdk, coreLibraryConfig, artJarPath);
    }
    await _relocateDesugarHelpers(artJarPath);
  }

  Future<String> _extractCoreLibraryConfig() async {
    final configJar = ZipDecoder().decodeBytes(
        await (await _libService.coreLibraryConfigJar())
            .asFile()
            .readAsBytes());
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
          minSdk: minSdk,
          coreLibraryConfig: coreLibraryConfig,
          output: library);
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

  static String _aarFileName(Artifact aar) => aar.isMavenArtifact
      ? '${aar.coordinate.replaceAll(':', '-')}.aar'
      : p.basename(aar.artifactFile);

  Future<String> _createArtJar(Set<String> requiredJars) async {
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
    final rawDir = _fs.buildRawDir.path;
    final components = await _readJsonList(p.join(rawDir, 'components.json'));
    final buildInfos = await _readJsonList(
        p.join(rawDir, 'files', 'component_build_infos.json'));

    final outputDir = p.join(_fs.cwd, 'out').asDir(true);
    final aix = p.join(outputDir.path, '$org.aix');
    await writeZip(aix, [
      for (final entry in aixEntries(components, buildInfos))
        ArchiveFile.bytes(
            '$org/$entry', await p.join(rawDir, entry).asFile().readAsBytes()),
    ]);
    _lgr.info('Generated AIX file at ${aix.blue()}');

    final docs = p.join(outputDir.path, '$org.md');
    await docs.asFile().writeAsString(markdownDocs(components));
    _lgr.info('Generated docs at ${docs.blue()}');
  }

  static Future<List<Map<String, dynamic>>> _readJsonList(String path) async =>
      (jsonDecode(await path.asFile().readAsString()) as List)
          .cast<Map<String, dynamic>>();
}

class _BuildFailed implements Exception {
  const _BuildFailed();
}
