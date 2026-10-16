import 'dart:convert' show jsonEncode;
import 'dart:io'
    show
        Directory,
        File,
        FileSystemEntity,
        FileSystemEntityType,
        ProcessException;

import 'package:args/command_runner.dart';
import 'package:get_it/get_it.dart';
import 'package:hive/hive.dart';
import 'package:path/path.dart' as p;
import 'package:tint/tint.dart';

import 'package:rush/src/commands/build/aar_packager.dart';
import 'package:rush/src/commands/build/aix_assembly.dart';
import 'package:rush/src/commands/build/descriptor.dart';
import 'package:rush/src/commands/build/library_plan.dart';
import 'package:rush/src/commands/build/private_libraries.dart';
import 'package:rush/src/commands/build/project_libraries.dart';
import 'package:rush/src/commands/build/resources.dart';
import 'package:rush/src/commands/build/runtime_jar.dart';
import 'package:rush/src/commands/build/toolchain.dart';
import 'package:rush/src/commands/deps/sync.dart';
import 'package:rush/src/commands/build/tools/compiler.dart';
import 'package:rush/src/commands/build/tools/executor.dart';
import 'package:rush/src/config/config.dart';
import 'package:rush/src/services/ai2_runtime.dart';
import 'package:rush/src/services/lib_service.dart';
import 'package:rush/src/services/file_service.dart';
import 'package:rush/src/services/logger.dart';
import 'package:rush/src/utils/constants.dart';
import 'package:rush/src/utils/content_key.dart';
import 'package:rush/src/utils/file_extension.dart';
import 'package:rush/src/utils/error_message.dart';
import 'package:rush/src/version.dart';

class BuildCommand extends Command<int> {
  final Logger _lgr = GetIt.I<Logger>();
  final FileService _fs = GetIt.I<FileService>();
  late final LibService _libService;

  BuildCommand() {
    argParser.addFlag(
      'optimize',
      abbr: 'o',
      help: 'Optimizes, shrinks and obfuscates extension\'s code using R8.',
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

    final (plan, resources) = await _task('Compiling sources', () async {
      final plan = await planProjectLibraries(_libService, config);
      _reportProblems(plan.problems);
      final timestampBox = await Hive.openLazyBox<DateTime>(timestampBoxName);
      final manifest = await _mergeManifests(config, plan.manifests);
      final resources = await ExtensionResources.compile(config, [
        for (final library in [
          ...plan.shared,
          ...plan.private,
          ...plan.provided
        ])
          if (library.isAar) library.file,
      ]);
      await _compile(config, plan, manifest, timestampBox, resources);
      return (plan, resources);
    });

    final (extension, artJarPath, privateLibraries) =
        await _task('Processing', () async {
      final extension = await _requireExtension();
      await removeMapping(extension.package);
      return (
        extension,
        await createArtJar(plan.privateJars),
        await PrivateLibraries.prepare(config, plan),
      );
    });

    final program = optimize || !privateLibraries.isEmpty
        ? await _task(
            optimize
                ? 'Optimizing and obfuscating the bytecode'
                : 'Shrinking bundled libraries',
            () => shrinkProgram(
                artJarPath, plan, resources, extension, privateLibraries,
                optimize: optimize))
        : PrivateProgram.none(config, extension.package);

    final (descriptor, libraries) =
        await _task('Packaging libraries', () async {
      if (!privateLibraries.isEmpty) {
        await relocatePrivateClasses(artJarPath, program);
      }
      return (
        extension.withBuildInfos(
            program.names.renameBuildInfos(extension.buildInfos)),
        writeLongIdResources(await moveLibraryFontsToRaw([
          ...await packageLibraries(config, plan, resources, program.names),
          ...await program.packageAars(artJarPath),
        ])),
      );
    });

    await _task(
        'Desugaring Java 8+ language features',
        () => desugarArtJar(config, artJarPath, plan, descriptor.package,
            program.relocatedAarClasses));
    await _task(
        'Generating DEX bytecode',
        () => _dex(config, artJarPath,
            {...plan.libraryJars, ...program.relocatedAarClasses}));
    await _task('Packaging the extension',
        () => assembleAix(config, descriptor, libraries));
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
    for (final key in config.deprecatedKeys) {
      _lgr.warn('`$key` in rush.yml is deprecated. Run `rush migrate` to '
          'move its libraries to `dependencies`, placed as provided under '
          '`libraries`.');
    }
    for (final key in config.ignoredKeys) {
      _lgr.warn('`$key` in rush.yml has no effect. Remove it.');
    }
    await checkProjectRules();
    final missingFiles = _missingFiles(config);
    for (final path in missingFiles) {
      _lgr.err('$path is listed in rush.yml but doesn\'t exist');
    }
    if (missingFiles.isNotEmpty) {
      throw Exception();
    }
    return config;
  }

  void _reportProblems(List<Problem> problems) {
    for (final problem in problems) {
      problem.isError ? _lgr.err(problem.message) : _lgr.warn(problem.message);
    }
    if (problems.any((el) => el.isError)) {
      throw Exception();
    }
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
        for (final dependency in config.dependencies)
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
  Future<void> _compile(Config config, LibraryPlan plan, String manifest,
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
      ...plan.compileClasspath,
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
}

class _BuildFailed implements Exception {
  const _BuildFailed();
}
