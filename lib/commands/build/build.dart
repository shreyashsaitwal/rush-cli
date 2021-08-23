import 'dart:io' show File, Directory, exit;

import 'package:archive/archive_io.dart';
import 'package:args/command_runner.dart';
import 'package:checked_yaml/checked_yaml.dart';
import 'package:collection/collection.dart';
import 'package:dart_console/dart_console.dart';
import 'package:hive/hive.dart';
import 'package:path/path.dart' as p;
import 'package:rush_cli/commands/build/helpers/build_utils.dart';
import 'package:rush_cli/commands/build/models/rush_yaml.dart';
import 'package:rush_cli/commands/build/models/rush_lock.dart';
import 'package:rush_cli/commands/build/tools/compiler.dart';
import 'package:rush_cli/commands/build/tools/desugarer.dart';
import 'package:rush_cli/commands/build/tools/executor.dart';
import 'package:rush_cli/commands/build/tools/generator.dart';
import 'package:rush_prompt/rush_prompt.dart';

class BuildCommand extends Command {
  final String _cd;
  final String _dataDir;

  late final DateTime _startTime;

  BuildCommand(this._cd, this._dataDir) {
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

    File yamlFile;
    try {
      yamlFile = BuildUtils.getRushYaml(_cd);
    } catch (_) {
      valStep
        ..log(LogType.erro, 'Metadata file (rush.yml) not found')
        ..finishNotOk();

      BuildUtils.printFailMsg(
          BuildUtils.getTimeDifference(_startTime, DateTime.now()));
      exit(2);
    }

    Hive.init(p.join(_cd, '.rush'));
    final dataBox = await Hive.openBox('data');

    valStep.log(LogType.info, 'Checking metadata file (rush.yml)');
    final RushYaml rushYaml;
    try {
      rushYaml = checkedYamlDecode(
        yamlFile.readAsStringSync(),
        (json) => RushYaml.fromJson(json!, valStep),
        sourceUrl: Uri.tryParse(
            'https://raw.githubusercontent.com/shreyashsaitwal/rush-cli/main/schema/rush.yml'),
      );

      await BuildUtils.ensureBoxValues(_cd, dataBox, rushYaml);
    } on ParsedYamlException catch (e) {
      valStep.log(LogType.erro,
          'The following error occurred while validating metadata file (rush.yml):');

      e.message.split('\n').forEach((element) {
        valStep.log(LogType.erro, ' ' * 5 + element, addPrefix: false);
      });

      valStep.finishNotOk();
      BuildUtils.printFailMsg(
          BuildUtils.getTimeDifference(_startTime, DateTime.now()));
      exit(2);
    } catch (e) {
      valStep.log(LogType.erro,
          'The following error occurred while validating metadata file (rush.yml):');

      if (e.toString().contains('\n')) {
        e.toString().split('\n').forEach((element) {
          valStep.log(LogType.erro, ' ' * 5 + element, addPrefix: false);
        });
      } else {
        valStep.log(LogType.erro, ' ' * 5 + e.toString(), addPrefix: false);
      }
      valStep.finishNotOk();
      BuildUtils.printFailMsg(
          BuildUtils.getTimeDifference(_startTime, DateTime.now()));
      exit(2);
    }

    valStep.log(LogType.info, 'Checking AndroidManifest.xml file');

    final manifestFile = File(p.join(_cd, 'src', 'AndroidManifest.xml'));
    if (!manifestFile.existsSync()) {
      valStep
        ..log(LogType.erro, 'AndroidManifest.xml not found')
        ..finishNotOk();
      BuildUtils.printFailMsg(
          BuildUtils.getTimeDifference(_startTime, DateTime.now()));
      exit(1);
    }

    valStep.finishOk();

    if (await BuildUtils.areInfoFilesModified(_cd, dataBox)) {
      BuildUtils.cleanWorkspaceDir(
          _dataDir, await dataBox.get('org') as String);
    }

    // Increment version number if this is a production build.
    final isRelease = argResults!['release'] as bool;
    if (isRelease) {
      final extVerYml = rushYaml.version.number;

      if (extVerYml == 'auto') {
        final extVerBox = await dataBox.get('version') ?? 0;
        await dataBox.put('version', extVerBox + 1);
      }

      BuildUtils.cleanWorkspaceDir(
          _dataDir, await dataBox.get('org') as String);
    }

    final optimize =
        BuildUtils.needsOptimization(isRelease, argResults!, rushYaml);

    // Delete the dev-deps dir if it exists
    final devDeps = Directory(p.join(_cd, '.rush', 'dev-deps'));
    BuildUtils.updateDevDepsXml(_cd, _dataDir);
    if (devDeps.existsSync()) devDeps.deleteSync(recursive: true);

    final rushLock = await _resolveDeps(rushYaml, dataBox);
    await _compile(dataBox, optimize, rushYaml.build?.kotlin?.enable ?? false,
        rushYaml, rushLock);
  }

  Future<RushLock?> _resolveDeps(RushYaml rushYaml, Box dataBox) async {
    final containsRemoteDeps =
        rushYaml.deps?.any((el) => el.value().contains(':')) ?? false;
    if (!containsRemoteDeps) {
      return null;
    }

    final step = BuildStep('Resolving dependencies')..init();

    final lastResolvedDeps =
        await dataBox.get('deps', defaultValue: <String>[]) as List<String>;
    final currentRemoteDeps = rushYaml.deps
            ?.where((el) => el.value().contains(':'))
            .map((el) => el.value())
            .toList() ??
        <String>[];

    final areDepsUpToDate = DeepCollectionEquality.unordered()
        .equals(lastResolvedDeps, currentRemoteDeps);

    final lockFile = File(p.join(_cd, '.rush', 'rush.lock'));
    final lastResolveTime = await dataBox.get('lastResolveTime',
        defaultValue: DateTime.now()) as DateTime;

    if (!areDepsUpToDate ||
        !lockFile.existsSync() ||
        lockFile.lastModifiedSync().isAfter(lastResolveTime)) {
      try {
        await Executor(_cd, _dataDir).execResolver();
      } catch (e) {
        step.finishNotOk();
        BuildUtils.printFailMsg(
            BuildUtils.getTimeDifference(_startTime, DateTime.now()));
        exit(1);
      } finally {
        await Future.wait([
          dataBox.put('deps', currentRemoteDeps),
          dataBox.put('lastResolveTime', DateTime.now())
        ]);
      }
    } else {
      step.log(LogType.info, 'Everything is up-to-date!');
    }

    final RushLock rushLock;
    try {
      rushLock = checkedYamlDecode(
          File(p.join(_cd, '.rush', 'rush.lock')).readAsStringSync(),
          (json) => RushLock.fromJson(json!));
    } catch (e) {
      step.log(LogType.erro, e.toString());
      exit(1);
    }

    step.finishOk();
    return rushLock;
  }

  /// Compiles extension's source files.
  Future<void> _compile(Box dataBox, bool optimize, bool enableKt,
      RushYaml rushYaml, RushLock? rushLock) async {
    final compileStep = BuildStep('Compiling sources')..init();

    if (rushLock != null) {
      _mergeManifests(dataBox, rushLock, compileStep, rushYaml.minSdk ?? 7);
    }

    final srcFiles = Directory(p.join(_cd, 'src'))
        .listSync(recursive: true)
        .whereType<File>();

    final javaFiles = srcFiles
        .whereType<File>()
        .where((file) => p.extension(file.path) == '.java');
    final ktFiles = srcFiles
        .whereType<File>()
        .where((file) => p.extension(file.path) == '.kt');

    final count = javaFiles.length + ktFiles.length;
    compileStep.log(
        LogType.info, 'Picked $count source file' + (count > 1 ? 's' : ''));

    try {
      final compiler = Compiler(_cd, _dataDir);
      if (ktFiles.isNotEmpty) {
        if (!enableKt) {
          compileStep
            ..log(LogType.erro,
                'Kotlin files detected. Please enable Kotlin in rush.yml.')
            ..finishNotOk();
          exit(1);
        }

        await compiler.compileKt(dataBox, compileStep, rushYaml, rushLock);
      }

      if (javaFiles.isNotEmpty) {
        await compiler.compileJava(dataBox, compileStep, rushYaml, rushLock);
      }
    } catch (e) {
      compileStep.finishNotOk();
      BuildUtils.printFailMsg(
          BuildUtils.getTimeDifference(_startTime, DateTime.now()));
      await BuildUtils.emptyBuildBox();
      exit(1);
    }

    compileStep.finishOk();

    final org = await dataBox.get('org') as String;
    final deJet = argResults!['support-lib'] as bool;
    await _process(org, optimize, deJet, rushYaml, rushLock);
  }

  Future<void> _mergeManifests(
      Box dataBox, RushLock rushLock, BuildStep step, int minSdk) async {
    final lastMerge = await dataBox.get('lastManifMerge',
        defaultValue: DateTime.now()) as DateTime;

    final depManifests =
        rushLock.resolvedDeps.where((el) => el.type == 'aar').map((el) {
      final outputDir = Directory(p.join(
          p.dirname(el.localPath), p.basenameWithoutExtension(el.localPath)))
        ..createSync(recursive: true);
      return p.join(outputDir.path, 'AndroidManifest.xml');
    }).toList();

    final areDepManifestsMod = depManifests.any((el) {
      final file = File(el);
      // If the file doesn't exist, chances are it was deleted by someone. Just
      // to be sure, unzip the AAR again.
      if (!file.existsSync()) {
        BuildUtils.unzip(p.dirname(el) + '.aar', p.dirname(el));
      }

      if (file.existsSync()) {
        return file.lastModifiedSync().isAfter(lastMerge);
      } else {
        depManifests.remove(el);
      }
      return false;
    });

    final org = dataBox.get('org') as String;

    final mainManifest = File(p.join(_cd, 'src', 'AndroidManifest.xml'));
    final output =
        File(p.join(_dataDir, 'workspaces', org, 'files', 'MergedManifest.xml'));

    final conditions = !output.existsSync() ||
        mainManifest.lastModifiedSync().isAfter(lastMerge) ||
        areDepManifestsMod;
    if (conditions) {
      step.log(
          LogType.info, 'Merging main AndroidManifest.xml with that from deps');

      try {
        await Executor(_cd, _dataDir)
            .execManifMerger(minSdk, mainManifest.path, depManifests, output.path);
      } catch (e) {
        step.finishNotOk();
        BuildUtils.printFailMsg(
            BuildUtils.getTimeDifference(_startTime, DateTime.now()));
        await BuildUtils.emptyBuildBox();
        exit(1);
      }
    }
  }

  /// Further process the extension by generating extension files, adding
  /// libraries and jaring the extension.
  Future<void> _process(String org, bool optimize, bool deJet,
      RushYaml rushYaml, RushLock? rushLock) async {
    final BuildStep processStep;
    final rulesPro = File(p.join(_cd, 'src', 'proguard-rules.pro'));

    processStep = BuildStep('Processing the extension')..init();
    if (!rulesPro.existsSync() && optimize) {
      processStep.log(LogType.warn,
          'Unable to find \'proguard-rules.pro\' in \'src\' directory.');
      optimize = false;
    }

    if (rushYaml.build?.desugar?.enable ?? false) {
      processStep.log(LogType.info, 'Desugaring Java 8 language features');
      final desugarer = Desugarer(_cd, _dataDir);
      try {
        await desugarer.run(org, rushYaml, processStep, rushLock);
      } catch (e) {
        processStep.finishNotOk();
        BuildUtils.printFailMsg(
            BuildUtils.getTimeDifference(_startTime, DateTime.now()));
        await BuildUtils.emptyBuildBox();
        exit(1);
      }
    }

    // Generate the extension files
    if (rushYaml.deps?.isEmpty ?? true) {
      processStep.log(LogType.info, 'Linking extension assets');
    } else {
      processStep.log(
          LogType.info, 'Linking extension assets and dependencies');
    }

    await Generator(_cd, _dataDir)
        .generate(org, processStep, rushYaml, rushLock);

    // Create a JAR containing the contents of extension's dependencies and
    // compiled source files
    final artJar =
        await _generateArtJar(org, processStep, optimize, rushYaml, rushLock);

    // Copy ART to raw dir
    if (artJar.existsSync()) {
      final destDir = Directory(
          p.join(_dataDir, 'workspaces', org, 'raw', 'x', org, 'files'))
        ..createSync(recursive: true);

      artJar.copySync(p.join(destDir.path, 'AndroidRuntime.jar'));
    } else {
      processStep
        ..log(LogType.erro, 'File not found: ' + artJar.path)
        ..finishNotOk();

      BuildUtils.printFailMsg(
          BuildUtils.getTimeDifference(_startTime, DateTime.now()));
      exit(1);
    }

    var needDeJet = deJet;
    if (deJet) {
      processStep.log(LogType.info, 'De-jetifing the extension');

      try {
        needDeJet =
            await Executor(_cd, _dataDir).execDeJetifier(org, processStep);
      } catch (e) {
        processStep.finishNotOk();
        BuildUtils.printFailMsg(
            BuildUtils.getTimeDifference(_startTime, DateTime.now()));
        exit(1);
      }

      if (!needDeJet && deJet) {
        // Delete the raw/sup directory so that support version of the extension
        // isn't generated.
        Directory(p.join(_dataDir, 'workspaces', org, 'raw', 'sup'))
            .deleteSync(recursive: true);

        processStep.log(LogType.warn,
            'No references to AndroidX packages were found. You don\'t need to pass the `-s` flag for now.');
      }
    }

    processStep.log(LogType.info, 'Generating DEX bytecode');
    try {
      await _dex(org, needDeJet, processStep);
    } catch (e) {
      processStep.finishNotOk();
      BuildUtils.printFailMsg(
          BuildUtils.getTimeDifference(_startTime, DateTime.now()));
      exit(1);
    }

    processStep.finishOk();
    _assemble(org);
  }

  /// JAR the compiled class files and third-party dependencies into a single JAR.
  Future<File> _generateArtJar(String org, BuildStep processStep, bool optimize,
      RushYaml rushYaml, RushLock? rushLock) async {
    final artDir = Directory(p.join(_dataDir, 'workspaces', org, 'art'));

    final artJar =
        File(p.join(artDir.path, 'ART.jar')); // ART == Android Runtime

    final zipEncoder = ZipFileEncoder()..open(artJar.path);

    artDir.listSync(recursive: true)
      ..whereType<File>()
          .where((el) => p.extension(el.path) == '.kotlin_module')
          .forEach((el) {
        el.deleteSync();
      })
      ..whereType<Directory>()
          .where((el) => el.path.endsWith(p.join('META-INF', 'versions')))
          .forEach((el) {
        el.deleteSync(recursive: true);
      });

    for (final entity in artDir.listSync()) {
      if (entity is File && p.extension(entity.path) == '.class') {
        zipEncoder.addFile(entity);
      } else if (entity is Directory) {
        zipEncoder.addDirectory(entity);
      }
    }
    zipEncoder.close();

    try {
      if (optimize) {
        await _optimizeArt(artJar, org, processStep, rushYaml, rushLock);
      }
    } catch (e) {
      processStep.finishNotOk();
      BuildUtils.printFailMsg(
          BuildUtils.getTimeDifference(_startTime, DateTime.now()));
      exit(1);
    }

    return artJar;
  }

  Future<void> _optimizeArt(File artJar, String org, BuildStep processStep,
      RushYaml rushYaml, RushLock? rushLock) async {
    final executor = Executor(_cd, _dataDir);

    processStep.log(LogType.info, 'Optimizing the extension');
    await executor.execProGuard(org, processStep, rushYaml, rushLock);

    // Delete the old non-optimized JAR...
    artJar.deleteSync();

    // ...and rename the optimized JAR with old JAR's name
    File(p.join(p.dirname(artJar.path), 'ART.opt.jar'))
      ..copySync(artJar.path)
      ..deleteSync(recursive: true);
  }

  /// Convert generated extension JAR file from previous step into DEX bytecode.
  Future<void> _dex(String org, bool deJet, BuildStep processStep) async {
    final executor = Executor(_cd, _dataDir);

    if (deJet) {
      await Future.wait([
        executor.execD8(org, processStep, deJet: true),
        executor.execD8(org, processStep),
      ]);
    } else {
      await executor.execD8(org, processStep);
    }
  }

  /// Finalize the build.
  void _assemble(String org) {
    final assembleStep = BuildStep('Finalizing the build')..init();

    final rawDirX = Directory(p.join(_dataDir, 'workspaces', org, 'raw', 'x'));
    final rawDirSup =
        Directory(p.join(_dataDir, 'workspaces', org, 'raw', 'sup'));

    final outputDir = Directory(p.join(_cd, 'out'))
      ..createSync(recursive: true);

    final zipEncoder = ZipFileEncoder();

    try {
      assembleStep.log(LogType.info, 'Packing $org.aix');
      zipEncoder.zipDirectory(rawDirX,
          filename: p.join(outputDir.path, '$org.aix'));

      if (rawDirSup.existsSync()) {
        assembleStep.log(LogType.info, 'Packing $org.support.aix');
        zipEncoder.zipDirectory(rawDirSup,
            filename: p.join(outputDir.path, '$org.support.aix'));
      }
    } catch (e) {
      assembleStep
        ..log(LogType.erro,
            'Something went wrong while trying to pack the extension.')
        ..log(LogType.erro, e.toString(), addPrefix: false)
        ..finishNotOk();
      exit(1);
    }

    assembleStep.finishOk();

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
