import 'dart:convert' show jsonEncode, utf8;
import 'dart:io'
    show
        Directory,
        File,
        FileSystemEntity,
        FileSystemEntityType,
        Platform,
        ProcessException;

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
import 'package:rush/src/commands/build/descriptor.dart';
import 'package:rush/src/commands/build/fixes/raw_fonts.dart';
import 'package:rush/src/commands/build/libraries.dart';
import 'package:rush/src/commands/build/proguard_rules.dart';
import 'package:rush/src/commands/build/relocation.dart';
import 'package:rush/src/commands/build/docs.dart';
import 'package:rush/src/commands/build/resources.dart';
import 'package:rush/src/commands/build/toolchain.dart';
import 'package:rush/src/commands/build/utils.dart';
import 'package:rush/src/commands/deps/sync.dart';
import 'package:rush/src/commands/build/tools/compiler.dart';
import 'package:rush/src/commands/build/tools/executor.dart';
import 'package:rush/src/commands/build/tools/library_desugarer.dart';
import 'package:rush/src/config/config.dart';
import 'package:rush/src/resolver/artifact.dart';
import 'package:rush/src/services/ai2_runtime.dart';
import 'package:rush/src/services/lib_service.dart';
import 'package:rush/src/services/file_service.dart';
import 'package:rush/src/services/logger.dart';
import 'package:rush/src/utils/constants.dart';
import 'package:rush/src/utils/content_key.dart';
import 'package:rush/src/utils/file_extension.dart';
import 'package:rush/src/utils/error_message.dart';
import 'package:rush/src/utils/zip.dart';
import 'package:rush/src/version.dart';

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
      final manifest = await _mergeManifests(config, deps.aarManifests);
      await _warnAboutDuplicateAars(deps.shippedAars);
      final resources = await ExtensionResources.compile(config);
      await _compile(config, deps, manifest, timestampBox, resources);
      return (deps, resources);
    });

    final (descriptor, libraries, artJarPath) =
        await _task('Processing', () async {
      final descriptor = await _requireExtension();
      final libraries = await _moveFontsToRaw(
          await _packageLibraries(config, deps, resources));
      return (descriptor, libraries, await _createArtJar(deps.privateJars));
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
      await _task(
          'Relocating bundled libraries',
          () => _relocatePrivateClasses(
              artJarPath, deps.privateJars, descriptor.package));
    }

    await _task('Desugaring Java 8+ language features',
        () => _desugarArtJar(config, artJarPath, deps, descriptor.package));
    await _task('Generating DEX bytecode',
        () => _dex(config, artJarPath, deps.referencedJars));
    await _task('Packaging the extension',
        () => _assemble(config, descriptor, libraries));
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

  Future<Descriptor> _requireExtension() async {
    final descriptor = await Descriptor.read(_fs.buildRawDir.path);
    if (descriptor == null) {
      _lgr
        ..err('No extension found')
        ..log('Annotate the extension class with @Extension', 'help  '.green());
      throw Exception();
    }
    return descriptor;
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
    for (final MapEntry(key: package, value: copies)
        in duplicateLibraries(packages).entries) {
      _lgr.warn('${copies.join(' and ')} are the same library ($package). '
          'App Inventor includes only one of them in the app, so remove '
          'the others from rush.yml.');
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

  Future<String> _mergeManifests(Config config, List<String> manifests) async {
    final mainManifest =
        p.join(_fs.srcDir.path, 'AndroidManifest.xml').asFile();
    final outputManifest =
        p.join(_fs.buildFilesDir.path, 'AndroidManifest.xml').asFile(true);

    if (manifests.isEmpty) {
      _lgr.dbg('No manifests found in dependencies; skipping manifest merge');
      await outputManifest.delete();
      return mainManifest.path;
    }

    _lgr.info('Merging Android manifests...');
    await Executor.execManifMerger(
      config.minSdk,
      mainManifest.path,
      manifests.toSet(),
    );
    return outputManifest.path;
  }

  /// Compiles extension's source files.
  Future<void> _compile(Config config, BuildDependencies deps, String manifest,
      LazyBox<DateTime> timestampBox, ExtensionResources? resources) async {
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

    final compileClasspathJars = {
      ...deps.compileClasspath,
      if (resources != null) resources.classesDir,
    };

    final configJson = p.join(_fs.buildDir.path, 'config.json').asFile(true);
    await configJson.writeAsString(jsonEncode(config.toJson()));
    final processorOptions =
        p.join(_fs.buildDir.path, 'processor.json').asFile(true);
    await processorOptions.writeAsString(jsonEncode({
      'config': configJson.path,
      'manifest': manifest,
      'output': _fs.buildRawDir.path,
      'project': _fs.cwd,
      'helperClasspath': [
        _fs.buildClassesDir.path,
        _libService.annotationsJar,
        (await Ai2Runtime.load()).runtimeJar,
      ],
      'version': packageVersion,
    }));

    final key = ContentKey()
      ..add('toolchain', await toolchainKey)
      ..add('kotlin', config.kotlin.compilerVersion);
    await key.addFile('processor', _libService.processorJar);
    await key.addFile('config', configJson.path);
    await key.addFile('manifest', manifest);
    await key.addPath('src', _fs.srcDir.path);
    await key.addPath('assets', p.join(_fs.cwd, 'assets'));
    if (config.license.isNotEmpty) {
      await key.addPath('license', p.join(_fs.cwd, config.license));
    }
    for (final (i, entry) in compileClasspathJars.indexed) {
      await key.addPath('classpath $i', entry);
    }

    await _unlessUnchanged(
      'compile',
      key.value,
      outputs: [
        _fs.buildClassesDir.path,
        p.join(_fs.buildRawDir.path, 'components.json'),
      ],
      run: () => Compiler.compile(
        compileClasspathJars,
        javaFiles: javaFiles.map((file) => file.path).toSet(),
        kotlinFiles: ktFiles.map((file) => file.path).toSet(),
        kotlinVersion: config.kotlin.compilerVersion,
        timestampBox: timestampBox,
        processorOptions: processorOptions.path,
      ),
    );
  }

  Future<void> _dex(
      Config config, String artJarPath, Set<String> classpath) async {
    final key = ContentKey()
      ..add('toolchain', await toolchainKey)
      ..add('min sdk', config.minSdk);
    await key.addFile('runtime', artJarPath);
    await key.addFile('r8', await _libService.r8Jar());
    for (final (i, jar) in classpath.indexed) {
      await key.addPath('classpath $i', jar);
    }
    await _unlessUnchanged(
      'dex',
      key.value,
      outputs: [p.join(_fs.buildRawDir.path, 'classes.jar')],
      run: () => Executor.execD8(config, artJarPath, classpath),
    );
  }

  static bool _present(String path) =>
      switch (FileSystemEntity.typeSync(path)) {
        FileSystemEntityType.directory => Directory(path).listSync().isNotEmpty,
        FileSystemEntityType.notFound => false,
        _ => true,
      };

  Future<void> _unlessUnchanged(String step, String key,
      {required List<String> outputs,
      required Future<void> Function() run}) async {
    final stamp = p.join(_fs.buildDir.path, '$step.key').asFile();
    if (await stamp.exists() &&
        await stamp.readAsString() == key &&
        outputs.every(_present)) {
      _lgr.info('Nothing changed since the last build, skipped the $step step');
      return;
    }
    if (await stamp.exists()) {
      await stamp.delete();
    }
    await run();
    await stamp.writeAsString(key);
  }

  Future<List<Library>> _packageLibraries(Config config, BuildDependencies deps,
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

  static Future<Map<Artifact, List<ArchiveFile>>> _sharedJarClasses(
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
    final projectRules = p.join(_fs.srcDir.path, 'proguard-rules.pro').asFile();
    await Executor.execProGuard(
      config,
      artJarPath,
      {...deps.referencedJars, if (resources != null) resources.classesDir},
      {
        ...deps.aarProguardRules,
        ...await _bundledProguardRules(deps.privateJars),
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

  Future<void> _relocatePrivateClasses(
      String artJarPath, Set<String> privateJars, String package) async {
    final classes = {
      for (final jar in privateJars)
        ...relocatableClasses(await _fileEntries(jar)),
    };
    _lgr.info('Moved ${privateJars.length} bundled libraries to '
        '${await _relocate(artJarPath, classes, package)}');
  }

  Future<void> _relocateDesugarHelpers(
      String artJarPath, String package) async {
    final helpers = desugarHelpers(await _fileEntries(artJarPath));
    if (helpers.isNotEmpty) {
      await _relocate(artJarPath, helpers, package);
    }
  }

  static Future<Iterable<String>> _fileEntries(String jar) async => ZipDecoder()
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

  Future<void> _desugarArtJar(Config config, String artJarPath,
      BuildDependencies deps, String package) async {
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
    await _relocateDesugarHelpers(artJarPath, package);
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

  Future<List<Library>> _moveFontsToRaw(List<Library> libraries) async {
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
          ArchiveFile.bytes(shimEntry,
              await p.join(classes, shimEntry).asFile().readAsBytes()),
        ])));
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

  Future<void> _assemble(
      Config config, Descriptor descriptor, List<Library> libraries) async {
    final org = descriptor.package;
    final components = descriptor.components;
    final buildInfos = [
      for (final info in descriptor.buildInfos)
        {...info, 'libraries': libraries.map((el) => el.fileName).toList()},
    ];
    final generated = {
      'files/component_build_infos.json': utf8.encode(jsonEncode(buildInfos)),
      for (final library in libraries)
        'aars/${library.fileName}': library.bytes,
    };

    final outputDir = p.join(_fs.cwd, 'out').asDir(true);
    final aix = p.join(outputDir.path, '$org.aix');
    await writeZip(aix, [
      for (final entry in aixEntries(components, buildInfos))
        ArchiveFile.bytes(
            '$org/$entry',
            generated[entry] ??
                await _entrySource(config, entry).readAsBytes()),
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
}

class _BuildFailed implements Exception {
  const _BuildFailed();
}
