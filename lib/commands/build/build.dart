import 'dart:convert';
import 'dart:io' show File, Directory, exit;

import 'package:archive/archive_io.dart';
import 'package:dart_console/dart_console.dart';
import 'package:hive/hive.dart';
import 'package:path/path.dart' as p;
import 'package:resolver/resolver.dart';
import 'package:rush_cli/commands/build/utils/build_utils.dart';
import 'package:rush_cli/commands/build/hive_adapters/build_box.dart';
import 'package:rush_cli/commands/deps/sync.dart';
import 'package:rush_cli/commands/rush_command.dart';
import 'package:rush_cli/models/rush_yaml/rush_yaml.dart';
import 'package:rush_cli/commands/build/tools/compiler.dart';
import 'package:rush_cli/commands/build/tools/desugarer.dart';
import 'package:rush_cli/commands/build/tools/executor.dart';
import 'package:rush_cli/commands/build/tools/generator.dart';
import 'package:rush_cli/services/file_service.dart';
import 'package:rush_cli/utils/cmd_utils.dart';
import 'package:rush_prompt/rush_prompt.dart';

import 'hive_adapters/remote_dep_index.dart';

class BuildCommand extends RushCommand {
  final FileService _fs;

  late final DateTime _startTime;
  late final RushYaml _rushYaml;
  late final Box<BuildBox> _buildBox;

  BuildCommand(this._fs) {
    argParser.addFlag(
      'optimize',
      abbr: 'o',
      help:
          'Optimizes, shrinks and obfuscates extension\'s Java bytecode using ProGuard.',
    );
  }

  @override
  String get description =>
      'Identifies and builds the extension project in current working directory.';

  @override
  String get name => 'build';

  /// Builds the extension in the current directory
  @override
  Future<void> run() async {
    _startTime = DateTime.now();

    Logger.logCustom('Build initialized\n',
        prefix: '• ', prefixFG: ConsoleColor.yellow);
    final valStep = BuildStep('Checking project files')..init();

    valStep.log(LogType.info, 'Checking metadata file (rush.yml)');
    _loadRushYaml(valStep);

    valStep.log(LogType.info, 'Checking AndroidManifest.xml file');
    final manifestFile = File(p.join(_fs.cwd, 'src', 'AndroidManifest.xml'));
    if (!manifestFile.existsSync()) {
      valStep
        ..log(LogType.erro, 'AndroidManifest.xml not found')
        ..finishNotOk();
      BuildUtils.printFailMsg(_startTime);
    }
    valStep.finishOk();

    _buildBox = await Hive.openBox<BuildBox>('build');

    if (_buildBox.isEmpty || _buildBox.getAt(0) == null) {
      await _buildBox.put('build', BuildBox.newInstance());
    }

    final optimize = () {
      if (argResults!['optimize'] as bool) {
        return true;
      }
      return false;
    }();

    final cachedDepIndex = await DepsSyncCommand(_fs).run();
    await _compile(optimize, cachedDepIndex);
  }

  void _loadRushYaml(BuildStep valStep) {
    try {
      _rushYaml = CmdUtils.loadRushYaml(_fs.cwd);
    } catch (e) {
      if (e.toString().contains('(rush.yml) not found')) {
        valStep
          ..log(LogType.erro, 'Metadata file (rush.yml) not found')
          ..finishNotOk();
        BuildUtils.printFailMsg(_startTime);
      }

      valStep.log(LogType.erro,
          'The following error occurred while validating metadata file (rush.yml):');
      if (e.toString().contains('\n')) {
        LineSplitter.split(e.toString()).forEach((element) {
          valStep.log(LogType.erro, ' ' * 5 + element, addPrefix: false);
        });
      } else {
        valStep.log(LogType.erro, ' ' * 5 + e.toString(), addPrefix: false);
      }

      valStep.finishNotOk();
      BuildUtils.printFailMsg(_startTime);
    }
  }

  /// Compiles extension's source files.
  Future<void> _compile(bool optimize, Set<RemoteDepIndex> depIndex) async {
    final compileStep = BuildStep('Compiling sources')..init();

    if (depIndex.isNotEmpty) {
      try {
        await _mergeManifests(
            compileStep, _rushYaml.android?.minSdk ?? 7, depIndex);
      } catch (e) {
        print(e);
      }
    }

    final srcFiles =
        Directory(_fs.srcDir).listSync(recursive: true).whereType<File>();

    final javaFiles = srcFiles
        .whereType<File>()
        .where((file) => p.extension(file.path) == '.java');
    final ktFiles = srcFiles
        .whereType<File>()
        .where((file) => p.extension(file.path) == '.kt');

    final count = javaFiles.length + ktFiles.length;
    compileStep.log(
        LogType.info, 'Picked $count source file' + (count > 1 ? 's' : ''));

    final compiler = Compiler(_fs, _rushYaml, _buildBox);
    final isKtEnabled = _rushYaml.kotlin?.enable ?? false;

    try {
      if (ktFiles.isNotEmpty) {
        if (!isKtEnabled) {
          compileStep
            ..log(LogType.erro,
                'Kotlin files detected. Please enable Kotlin in rush.yml.')
            ..finishNotOk();
          exit(1);
        }

        await compiler.compileKt(compileStep, depIndex);
      }
      if (javaFiles.isNotEmpty) {
        await compiler.compileJava(compileStep, depIndex);
      }
    } catch (e) {
      compileStep.finishNotOk();
      BuildUtils.printFailMsg(_startTime);
    }
    compileStep.finishOk();
    await _process(optimize, depIndex);
  }

  Future<void> _mergeManifests(
      BuildStep step, int minSdk, Set<RemoteDepIndex> depIndex) async {
    final lastMergeTime = _buildBox.getAt(0)!.lastManifestMergeTime;

    final manifestPaths = depIndex
        .where((el) => p.extension(el.artifactFile) == '.aar')
        .map((el) {
      final outputDir = Directory(p.withoutExtension(el.artifactFile))
        ..createSync(recursive: true);
      return p.join(outputDir.path, 'AndroidManifest.xml');
    }).toSet();

    if (manifestPaths.isEmpty) {
      return;
    }

    final areDepManifestsModified = manifestPaths.any((el) {
      final file = File(el);

      // If the manifest file doen't exist, unzip the AAR again to get it.
      if (!file.existsSync()) {
        BuildUtils.unzip(p.dirname(el) + '.aar', p.dirname(el));
        return true;
      }

      // If the file still doesn't exist, ignore it and move on.
      if (!file.existsSync()) {
        manifestPaths.remove(el);
        return false;
      }

      return file.lastModifiedSync().isAfter(lastMergeTime);
    });

    final mainManifest = File(p.join(_fs.srcDir, 'AndroidManifest.xml'));
    final outputManifest =
        File(p.join(_fs.buildDir, 'files', 'MergedManifest.xml'));

    final conditions = !outputManifest.existsSync() ||
        mainManifest.lastModifiedSync().isAfter(lastMergeTime) ||
        areDepManifestsModified;
    if (conditions) {
      step.log(LogType.info, 'Merging Android manifests');
      outputManifest.createSync(recursive: true);

      try {
        await Executor.execManifMerger(
            _fs, minSdk, mainManifest.path, manifestPaths);
      } catch (e) {
        step.finishNotOk();
        BuildUtils.printFailMsg(_startTime);
      }
    } else {
      step.log(LogType.info, 'Android manifests up-to-date');
    }
  }

  /// Further process the extension by generating extension files, adding
  /// libraries and jaring the extension.
  Future<void> _process(bool optimize, Set<RemoteDepIndex> depIndex) async {
    final BuildStep processStep;
    final rulesPro = File(p.join(_fs.srcDir, 'proguard-rules.pro'));

    processStep = BuildStep('Processing the extension')..init();
    if (!rulesPro.existsSync() && optimize) {
      processStep.log(LogType.warn,
          'Unable to find \'proguard-rules.pro\' in \'src\' directory.');
      optimize = false;
    }

    if (_rushYaml.desugar?.srcFiles ?? false) {
      processStep.log(LogType.info, 'Desugaring Java 8 language features');
      final desugarer = Desugarer(_fs, _rushYaml);
      try {
        await _buildBox.close();
        await desugarer.run(processStep, depIndex);
      } catch (e) {
        processStep.finishNotOk();
        BuildUtils.printFailMsg(_startTime);
      }
    }

    // Generate the extension files
    await Generator(_fs, _rushYaml).generate(processStep);

    // Create a JAR containing the contents of extension's dependencies and
    // compiled source files
    final File artJar;
    try {
      artJar = await _generateArtJar(processStep, depIndex, optimize);
    } catch (e) {
      if (e.toString().isNotEmpty && e.toString() != 'Exception') {
        processStep.log(LogType.erro, 'Something went wrong:');
        for (final line in LineSplitter.split(e.toString())) {
          processStep.log(LogType.erro, line, addPrefix: false);
        }
      }
      processStep.finishNotOk();
      BuildUtils.printFailMsg(_startTime);
      exit(1);
    }

    // Copy ART to raw dir
    if (artJar.existsSync()) {
      final destDir = Directory(p.join(_fs.buildDir, 'raw', 'files'))
        ..createSync(recursive: true);
      artJar
        ..copySync(p.join(destDir.path, 'AndroidRuntime.jar'))
        ..deleteSync();
    } else {
      processStep
        ..log(LogType.erro, 'File not found: ' + artJar.path)
        ..finishNotOk();
      BuildUtils.printFailMsg(_startTime);
    }

    processStep.log(LogType.info, 'Generating DEX bytecode');
    try {
      await Executor.execD8(_fs);
    } catch (e) {
      processStep.finishNotOk();
      BuildUtils.printFailMsg(_startTime);
    }

    processStep.finishOk();
    _assemble();
  }

  /// JAR the compiled class files and third-party dependencies into a single JAR.
  Future<File> _generateArtJar(
    BuildStep processStep,
    Set<RemoteDepIndex> depIndex,
    bool needOptimize,
  ) async {
    final pathEndsToIgnore = [
      '.kotlin_module',
      'META-INF/versions',
      '.jar',
    ];
    final artJarEncoder = ZipFileEncoder()
      ..create(p.join(_fs.buildDir, 'ART.jar'));

    final runtimeDeps = BuildUtils.depJarFiles(
        _fs.cwd, _rushYaml, DependencyScope.runtime, depIndex);

    // Add Kotlin Stdlib. to implDeps if Kotlin is enabled for the project.
    if (_rushYaml.kotlin?.enable ?? false) {
      runtimeDeps.add(p.join(_fs.devDepsDir, 'kotlin', 'kotlin-stdlib.jar'));
    }

    // Add class files from all required impl deps into the ART.jar
    if (runtimeDeps.isNotEmpty) {
      processStep.log(LogType.info, 'Attaching dependencies');
      final desugarStore = p.join(_fs.buildDir, 'files', 'desugar');

      for (final jarPath in runtimeDeps) {
        final jar = () {
          if (!(_rushYaml.desugar?.deps ?? false)) {
            return File(jarPath);
          } else {
            return File(p.join(desugarStore, p.basename(jarPath)));
          }
        }();

        if (!jar.existsSync()) {
          processStep
            ..log(LogType.erro, 'Unable to find required library \'$jar)\'')
            ..finishNotOk();
          exit(1);
        }

        final decodedJar =
            ZipDecoder().decodeBytes(jar.readAsBytesSync()).files;
        for (final file in decodedJar) {
          if (!pathEndsToIgnore.any((el) => file.name.endsWith(el))) {
            file.decompress();
            artJarEncoder.addArchiveFile(file);
          }
        }
      }
    }

    // Add extension classes to ART.jar
    final extensionClasses =
        Directory(p.join(_fs.buildDir, 'classes')).listSync(recursive: true);
    for (final entity in extensionClasses) {
      if (entity is File &&
          !pathEndsToIgnore.any((el) => entity.path.endsWith(el))) {
        final path =
            p.relative(entity.path, from: p.join(_fs.buildDir, 'classes'));
        await artJarEncoder.addFile(entity, path);
      }
    }
    artJarEncoder.close();

    final artJar = File(p.join(_fs.buildDir, 'ART.jar'));
    if (needOptimize) {
      processStep.log(LogType.info, 'Optimizing the extension');
      await _optimizeArt(artJar, depIndex);
    }
    return artJar;
  }

  Future<void> _optimizeArt(File artJar, Set<RemoteDepIndex> depIndex) async {
    await Executor.execProGuard(_fs, _rushYaml, depIndex);
    // Delete the old non-optimized JAR...
    artJar.deleteSync();
    // ...and rename the optimized JAR with old JAR's name
    File(p.join(p.dirname(artJar.path), 'ART.opt.jar'))
      ..copySync(artJar.path)
      ..deleteSync(recursive: true);
  }

  /// Finalize the build.
  void _assemble() {
    final assembleStep = BuildStep('Finalizing the build')..init();

    final org = () {
      final componentsJsonFile =
          File(p.join(_fs.buildDir, 'files', 'components.json'));

      final json = jsonDecode(componentsJsonFile.readAsStringSync());
      final type = json[0]['type'] as String;

      final split = type.split('.')..removeLast();
      return split.join('.');
    }();

    final rawDir = Directory(p.join(_fs.buildDir, 'raw'));
    final outputDir = Directory(p.join(_fs.cwd, 'out'))
      ..createSync(recursive: true);

    final zipEncoder = ZipFileEncoder();
    zipEncoder.create(p.join(outputDir.path, '$org.aix'));

    assembleStep.log(LogType.info, 'Packing $org.aix');
    try {
      for (final file in rawDir.listSync(recursive: true)) {
        if (file is File) {
          final name = p.relative(file.path, from: rawDir.path);
          zipEncoder.addFile(file, p.join(org, name));
        }
      }
    } catch (e) {
      assembleStep
        ..log(LogType.erro,
            'Something went wrong while trying to pack the extension.')
        ..log(LogType.erro, e.toString(), addPrefix: false)
        ..finishNotOk();
      exit(1);
    } finally {
      zipEncoder.close();
    }

    assembleStep.finishOk();
    _postAssemble();
  }

  void _postAssemble() {
    final timestamp = BuildUtils.getTimeDifference(_startTime, DateTime.now());

    final store = ErrWarnStore();
    var warn = '';

    final brightBlack = '\u001b[30;1m';
    final yellow = '\u001b[33m';
    final reset = '\u001b[0m';

    if (store.getWarnings > 0) {
      warn += '$brightBlack[$reset';
      warn += yellow;
      warn += store.getWarnings > 1
          ? '${store.getWarnings} warnings'
          : '${store.getWarnings} warning';
      warn += '$brightBlack]$reset';
    }

    Logger.logCustom('Build successful $timestamp $warn',
        prefix: '\n• ', prefixFG: ConsoleColor.brightGreen);
    exit(0);
  }
}
