import 'dart:convert';
import 'dart:io' show File, Directory, exit;

import 'package:archive/archive_io.dart';
import 'package:args/command_runner.dart';
import 'package:checked_yaml/checked_yaml.dart';
import 'package:collection/collection.dart';
import 'package:dart_console/dart_console.dart';
import 'package:hive/hive.dart';
import 'package:path/path.dart' as p;
import 'package:rush_cli/commands/build/utils/build_utils.dart';
import 'package:rush_cli/commands/build/hive_adapters/build_box.dart';
import 'package:rush_cli/commands/build/models/rush_lock/rush_lock.dart';
import 'package:rush_cli/commands/build/models/rush_yaml/rush_yaml.dart';
import 'package:rush_cli/commands/build/tools/compiler.dart';
import 'package:rush_cli/commands/build/tools/desugarer.dart';
import 'package:rush_cli/commands/build/tools/executor.dart';
import 'package:rush_cli/commands/build/tools/generator.dart';
import 'package:rush_cli/services/file_service.dart';
import 'package:rush_prompt/rush_prompt.dart';

class BuildCommand extends Command<void> {
  final FileService _fs;

  late final DateTime _startTime;
  late final RushYaml _rushYaml;
  late final Box<BuildBox> _buildBox;

  BuildCommand(this._fs) {
    argParser
      ..addFlag('release',
          abbr: 'r',
          defaultsTo: false,
          help: 'Marks this build as a release build.')
      ..addFlag('support-lib',
          abbr: 's',
          defaultsTo: false,
          help:
              'Generates two flavors of extensions, one that uses AndroidX libraries, '
              'and other that uses support libraries. The later is supposed to '
              'be used with builders that haven\'t yet migrated to AndroidX.')
      ..addFlag('optimize',
          abbr: 'o',
          defaultsTo: false,
          negatable: false,
          help:
              'Optimizes, shrinks and obfuscates extension\'s Java bytecode using ProGuard.')
      ..addFlag('no-optimize', negatable: false, defaultsTo: false);
  }

  @override
  String get description =>
      'Identifies and builds the extension project in current working directory.';

  @override
  String get name => 'build';

  @override
  void printUsage() {
    PrintArt();
    final console = Console();

    console
      ..setForegroundColor(ConsoleColor.cyan)
      ..write(' build: ')
      ..writeLine(description)
      ..writeLine()
      ..writeLine(' Usage: ')
      ..setForegroundColor(ConsoleColor.brightBlue)
      ..write('   rush ')
      ..setForegroundColor(ConsoleColor.cyan)
      ..writeLine('build')
      ..resetColorAttributes()
      ..writeLine();

    // Print available flags
    console
      ..writeLine(' Available flags:')
      ..setForegroundColor(ConsoleColor.yellow)
      ..write('   -r, --release')
      ..resetColorAttributes()
      ..writeLine(' ' * 9 + 'Marks this build as a release build.')
      ..setForegroundColor(ConsoleColor.yellow)
      ..write('   -s, --support-lib')
      ..resetColorAttributes()
      ..writeLine(' ' * 5 +
          'Generates two flavors of extensions, one that uses AndroidX libraries, '
              'and other that uses support libraries.')
      ..setForegroundColor(ConsoleColor.yellow)
      ..write('   -o, --[no-]optimize')
      ..resetColorAttributes()
      ..writeLine(' ' * 3 +
          'Optimize, obfuscates and shrinks your code with a set of ProGuard '
              'rules defined in proguard-rules.pro rules file.')
      ..resetColorAttributes()
      ..writeLine();
  }

  /// Builds the extension in the current directory
  @override
  Future<void> run() async {
    PrintArt();
    _startTime = DateTime.now();

    Logger.logCustom('Build initialized\n',
        prefix: '• ', prefixFG: ConsoleColor.yellow);
    final valStep = BuildStep('Checking project files')..init();

    valStep.log(LogType.info, 'Checking metadata file (rush.yml)');
    await _loadRushYaml(valStep);

    valStep.log(LogType.info, 'Checking AndroidManifest.xml file');
    final manifestFile = File(p.join(_fs.cwd, 'src', 'AndroidManifest.xml'));
    if (!manifestFile.existsSync()) {
      valStep
        ..log(LogType.erro, 'AndroidManifest.xml not found')
        ..finishNotOk();
      BuildUtils.printFailMsg(_startTime);
    }
    valStep.finishOk();

    Hive
      ..init(p.join(_fs.cwd, '.rush'))
      ..registerAdapter(BuildBoxAdapter());

    _buildBox = await Hive.openBox<BuildBox>('build');
    if (_buildBox.isEmpty || _buildBox.getAt(0) == null) {
      _buildBox.put(
        'build',
        BuildBox(
          lastResolvedDeps: [],
          lastResolution: DateTime.now(),
          kaptOpts: {'': ''},
          previouslyLogged: [],
          lastManifMerge: DateTime.now(),
        ),
      );
    }

    final optimize = () {
      if (argResults!['optimize'] as bool) {
        return true;
      }
      return false;
    }();

    final rushLock = await _resolveRemoteDeps();
    await _compile(optimize, rushLock);
  }

  Future<void> _loadRushYaml(BuildStep valStep) async {
    File yamlFile = () {
      final yml = File(p.join(_fs.cwd, 'rush.yml'));

      if (yml.existsSync()) {
        return yml;
      } else {
        final yaml = File(p.join(_fs.cwd, 'rush.yaml'));
        if (yaml.existsSync()) {
          return yaml;
        }
      }

      valStep
        ..log(LogType.erro, 'Metadata file (rush.yml) not found')
        ..finishNotOk();
      BuildUtils.printFailMsg(_startTime);
    }()!;

    try {
      _rushYaml = checkedYamlDecode(
        yamlFile.readAsStringSync(),
        (json) => RushYaml.fromJson(json!, valStep),
      );
    } catch (e) {
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

  Future<RushLock?> _resolveRemoteDeps() async {
    final containsRemoteDeps =
        _rushYaml.deps?.any((el) => el.value().contains(':')) ?? false;
    if (!containsRemoteDeps) {
      return null;
    }

    final step = BuildStep('Resolving dependencies')..init();
    final boxVal = _buildBox.getAt(0)!;

    final lastResolvedDeps = boxVal.lastResolvedDeps;
    final currentRemoteDeps = _rushYaml.deps
            ?.where((el) => el.value().contains(':'))
            .map((el) => el.value())
            .toList() ??
        <String>[];

    final areDepsUpToDate = DeepCollectionEquality.unordered()
        .equals(lastResolvedDeps, currentRemoteDeps);

    final lockFile = File(p.join(_fs.cwd, '.rush', 'rush.lock'));

    if (!areDepsUpToDate ||
        !lockFile.existsSync() ||
        lockFile.lastModifiedSync().isAfter(boxVal.lastResolution)) {
      try {
        await Executor.execResolver(_fs);
      } catch (e) {
        step.finishNotOk();
        BuildUtils.printFailMsg(_startTime);
      } finally {
        _buildBox.updateLastResolution(DateTime.now());
        _buildBox.updateLastResolvedDeps(currentRemoteDeps);
      }
    } else {
      step.log(LogType.info, 'Everything is up-to-date!');
    }

    final RushLock rushLock;
    try {
      rushLock = checkedYamlDecode(
          File(p.join(_fs.cwd, '.rush', 'rush.lock')).readAsStringSync(),
          (json) => RushLock.fromJson(json!));
    } catch (e) {
      step.log(LogType.erro, e.toString());
      exit(1);
    }

    step.finishOk();
    return rushLock;
  }

  /// Compiles extension's source files.
  Future<void> _compile(bool optimize, RushLock? rushLock) async {
    final compileStep = BuildStep('Compiling sources')..init();

    if (rushLock != null) {
      _mergeManifests(rushLock, compileStep, _rushYaml.android?.minSdk ?? 7);
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

        await compiler.compileKt(compileStep, rushLock);
      }
      if (javaFiles.isNotEmpty) {
        await compiler.compileJava(compileStep, rushLock);
      }
    } catch (e) {
      compileStep.finishNotOk();
      BuildUtils.printFailMsg(_startTime);
    }
    compileStep.finishOk();
    await _process(optimize, rushLock);
  }

  Future<void> _mergeManifests(
      RushLock rushLock, BuildStep step, int minSdk) async {
    final lastMerge = _buildBox.getAt(0)!.lastManifMerge;

    final depManifests =
        rushLock.resolvedDeps.where((el) => el.type == 'aar').map((el) {
      final outputDir = Directory(p.join(
          p.dirname(el.localPath), p.basenameWithoutExtension(el.localPath)))
        ..createSync(recursive: true);
      return p.join(outputDir.path, 'AndroidManifest.xml');
    }).toList();

    final areDepManifestsMod = depManifests.any((el) {
      final file = File(el);
      // If the file doesn't exist, chances are it was deleted. Just to be sure,
      // unzip the AAR again.
      if (!file.existsSync()) {
        BuildUtils.unzip(p.dirname(el) + '.aar', p.dirname(el));
      }

      // If the file still doesn't exist, then it means this AAR doesn't contain
      // any manifest file. Strange, but anyways.
      if (file.existsSync()) {
        return file.lastModifiedSync().isAfter(lastMerge);
      } else {
        depManifests.remove(el);
      }
      return false;
    });

    final mainManifest = File(p.join(_fs.srcDir, 'AndroidManifest.xml'));
    final output = File(p.join(_fs.buildDir, 'files', 'MergedManifest.xml'));

    final conditions = !output.existsSync() ||
        mainManifest.lastModifiedSync().isAfter(lastMerge) ||
        areDepManifestsMod;
    if (conditions) {
      step.log(LogType.info, 'Merging Android manifests');

      try {
        await Executor.execManifMerger(
            _fs, minSdk, mainManifest.path, depManifests);
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
  Future<void> _process(bool optimize, RushLock? rushLock) async {
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
        _buildBox.close();
        await desugarer.run(processStep, rushLock);
      } catch (e) {
        processStep.finishNotOk();
        BuildUtils.printFailMsg(_startTime);
      }
    }

    // Generate the extension files
    if (_rushYaml.deps?.isEmpty ?? true) {
      processStep.log(LogType.info, 'Linking extension assets');
    } else {
      processStep.log(
          LogType.info, 'Linking extension assets and dependencies');
    }

    await Generator(_fs, _rushYaml).generate(processStep, rushLock);

    // Create a JAR containing the contents of extension's dependencies and
    // compiled source files
    final artJar = await _generateArtJar(processStep, optimize, rushLock);

    // Copy ART to raw dir
    if (artJar.existsSync()) {
      final destDir = Directory(p.join(_fs.buildDir, 'raw', 'files'))
        ..createSync(recursive: true);

      artJar.copySync(p.join(destDir.path, 'AndroidRuntime.jar'));
    } else {
      processStep
        ..log(LogType.erro, 'File not found: ' + artJar.path)
        ..finishNotOk();

      BuildUtils.printFailMsg(_startTime);
    }

    processStep.log(LogType.info, 'Generating DEX bytecode');
    try {
      await Executor.execD8(_fs, processStep);
    } catch (e) {
      processStep.finishNotOk();
      BuildUtils.printFailMsg(_startTime);
    }

    processStep.finishOk();
    _assemble();
  }

  /// JAR the compiled class files and third-party dependencies into a single JAR.
  Future<File> _generateArtJar(
      BuildStep processStep, bool optimize, RushLock? rushLock) async {
    final artDir = Directory(p.join(_fs.buildDir, 'art'));

    final artJar =
        File(p.join(artDir.path, 'ART.jar')); // ART == Android Runtime

    final zipEncoder = ZipFileEncoder()..open(artJar.path);

    final pathEndToIgnore = [
      '.kotlin_module',
      'META-INF/versions',
      '.jar',
    ];

    for (final entity in artDir.listSync(recursive: true)) {
      if (!pathEndToIgnore.any((el) => entity.path.endsWith(el)) &&
          entity is File) {
        final path = p.relative(entity.path, from: artDir.path);
        zipEncoder.addFile(entity, path);
      }
    }
    zipEncoder.close();

    try {
      if (optimize) {
        await _optimizeArt(artJar, processStep, rushLock);
      }
    } catch (e) {
      processStep.finishNotOk();
      BuildUtils.printFailMsg(_startTime);
    }

    return artJar;
  }

  Future<void> _optimizeArt(
      File artJar, BuildStep processStep, RushLock? rushLock) async {
    processStep.log(LogType.info, 'Optimizing the extension');
    await Executor.execProGuard(_fs, processStep, _rushYaml, rushLock);

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
