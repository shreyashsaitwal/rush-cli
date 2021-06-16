import 'dart:io' show File, Directory, exit;

import 'package:archive/archive_io.dart';
import 'package:args/command_runner.dart';
import 'package:checked_yaml/checked_yaml.dart';
import 'package:dart_console/dart_console.dart';
import 'package:hive/hive.dart';
import 'package:path/path.dart' as p;
import 'package:rush_cli/commands/build_command/helpers/build_utils.dart';
import 'package:rush_cli/commands/build_command/helpers/compiler.dart';
import 'package:rush_cli/commands/build_command/helpers/desugarer.dart';
import 'package:rush_cli/commands/build_command/helpers/executor.dart';
import 'package:rush_cli/commands/build_command/helpers/generator.dart';
import 'package:rush_cli/commands/build_command/models/rush_yaml.dart';
import 'package:rush_prompt/rush_prompt.dart';

class BuildCommand extends Command {
  final String _cd;
  final String _dataDir;

  late final _startTime;

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
              'Generates two flavors of extensions, one that uses AndroidX libraries, and other that '
              'uses support libraries. The later is supposed to be used with builders that haven\'t '
              'yet migrated to AndroidX.')
      ..addFlag('optimize',
          abbr: 'o',
          defaultsTo: false,
          negatable: false,
          help:
              'Optimizes, skrinks and obfuscates extension\'s Java bytecode using ProGuard.')
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
          'Generates two flavors of extensions, one that uses AndroidX libraries, and other that '
              'uses support libraries.')
      ..setForegroundColor(ConsoleColor.yellow)
      ..write('   -o, --[no-]optimize')
      ..resetColorAttributes()
      ..writeLine(' ' * 3 +
          'Optimize, obfuscates and shrinks your code with a set of ProGuard rules defined in '
              'proguard-rules.pro rules file.')
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

    final manifestFile = File(p.join(_cd, 'src', 'AndroidManifest.xml'));
    if (!manifestFile.existsSync()) {
      valStep
        ..log(LogType.erro, 'AndroidManifest.xml not found')
        ..finishNotOk();

      BuildUtils.printFailMsg(
          BuildUtils.getTimeDifference(_startTime, DateTime.now()));
      exit(1);
    }

    valStep.log(LogType.info, 'AndroidManifest.xml file found');

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

    // This is done in case the user deletes the .rush directory.
    BuildUtils.copyDevDeps(_dataDir, _cd);

    final RushYaml rushYaml;
    try {
      rushYaml = checkedYamlDecode(
        yamlFile.readAsStringSync(),
        (json) => RushYaml.fromJson(json!, valStep),
        sourceUrl: Uri.tryParse(
            'https://raw.githubusercontent.com/shreyashsaitwal/rush-cli/main/schema/rush.json'),
      );

      await BuildUtils.ensureBoxValues(_cd, dataBox, rushYaml);
    } on ParsedYamlException catch (e) {
      valStep.log(LogType.erro,
          'The following error occurred while validating metadata file (rush.yml):');

      e.message.split('\n').forEach((element) {
        valStep.log(LogType.erro, ' ' * 7 + element, addPrefix: false);
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
          valStep.log(LogType.erro, ' ' * 7 + element, addPrefix: false);
        });
      } else {
        valStep.log(LogType.erro, ' ' * 7 + e.toString(), addPrefix: false);
      }

      valStep.finishNotOk();
      BuildUtils.printFailMsg(
          BuildUtils.getTimeDifference(_startTime, DateTime.now()));
      exit(2);
    }

    valStep
      ..log(LogType.info, 'Metadata file (rush.yml) found')
      ..finishOk();

    if (await BuildUtils.areInfoFilesModified(_cd, dataBox)) {
      BuildUtils.cleanWorkspaceDir(_dataDir, await dataBox.get('org'));
    }

    // Increment version number if this is a production build.
    final isRelease = argResults!['release'];
    if (isRelease) {
      final extVerYml = rushYaml.version.number;

      if (extVerYml == 'auto') {
        final extVerBox = await dataBox.get('version') ?? 0;
        await dataBox.put('version', extVerBox + 1);
      }

      BuildUtils.cleanWorkspaceDir(_dataDir, await dataBox.get('org'));
    }

    final optimize =
        BuildUtils.needsOptimization(isRelease, argResults!, rushYaml);

    await _compile(
        dataBox, optimize, rushYaml.build?.kotlin?.enable ?? false, rushYaml);
  }

  /// Compiles extension's source files
  Future<void> _compile(
      Box dataBox, bool optimize, bool enableKt, RushYaml rushYaml) async {
    final compileStep = BuildStep('Compiling source files')..init();
    final compiler = Compiler(_cd, _dataDir);

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
      if (ktFiles.isNotEmpty) {
        if (!enableKt) {
          compileStep
            ..log(LogType.erro,
                'Kotlin files detected. Please enable Kotlin in rush.yml.')
            ..finishNotOk();
          exit(1);
        }

        await compiler.compileKt(dataBox, compileStep);
      }

      if (javaFiles.isNotEmpty) {
        await compiler.compileJava(dataBox, compileStep);
      }
    } catch (e) {
      compileStep.finishNotOk();
      BuildUtils.printFailMsg(
          BuildUtils.getTimeDifference(_startTime, DateTime.now()));
      exit(1);
    }

    compileStep.finishOk();
    await _process(await dataBox.get('org'), optimize,
        argResults!['support-lib'], rushYaml);
  }

  /// Further process the extension by generating extension files, adding
  /// libraries and jaring the extension.
  Future<void> _process(
      String org, bool optimize, bool deJet, RushYaml rushYaml) async {
    final BuildStep processStep;
    final rulesPro = File(p.join(_cd, 'src', 'proguard-rules.pro'));

    processStep = BuildStep('Processing the extension')..init();
    if (!rulesPro.existsSync() && optimize) {
      processStep.log(LogType.warn,
          'Unable to find \'proguard-rules.pro\' in \'src\' directory.');
      optimize = false;
    }

    if (rushYaml.build?.desugar?.enable ?? false) {
      processStep.log(LogType.info, 'Desugaring Java 8 langauge features');
      final desugarer = Desugarer(_cd, _dataDir);
      await desugarer.run(org, rushYaml, processStep);
    }

    // Generate the extension files
    if (rushYaml.deps?.isEmpty ?? true) {
      processStep.log(LogType.info, 'Linking extension assets');
    } else {
      processStep.log(
          LogType.info, 'Linking extension assets and dependencies');
    }
    await Generator(_cd, _dataDir).generate(org, processStep, rushYaml);

    final executor = Executor(_cd, _dataDir);

    // Create a JAR containing the contents of extension's dependencies and
    // compiled source files
    final artJar = await _generateArtJar(org, processStep, optimize);

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
        needDeJet = await executor.execDeJetifier(org, processStep);
      } catch (e) {
        processStep.finishNotOk();

        BuildUtils.printFailMsg(
            BuildUtils.getTimeDifference(_startTime, DateTime.now()));

        exit(1);
      }

      if (!needDeJet && deJet) {
        // Delete the raw/sup directory so that support version of
        // the extension isn't generated.
        Directory(p.join(_dataDir, 'workspaces', org, 'raw', 'sup'))
            .deleteSync(recursive: true);

        processStep.log(LogType.warn,
            'No references to AndroidX packages were found. You don\'t need to pass the `-s` flag for now.');
      }
    }

    processStep.log(LogType.info, 'Dexing the extension');
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

  /// JAR the compiled class files and third-party dependencies into a
  /// single JAR.
  Future<File> _generateArtJar(
      String org, BuildStep processStep, bool optimize) async {
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
        await _optimizeArt(artJar, org, processStep);
      }
    } catch (e) {
      processStep.finishNotOk();
      BuildUtils.printFailMsg(
          BuildUtils.getTimeDifference(_startTime, DateTime.now()));
      exit(1);
    }

    return artJar;
  }

  Future<void> _optimizeArt(
      File artJar, String org, BuildStep processStep) async {
    final executor = Executor(_cd, _dataDir);

    processStep.log(LogType.info, 'Optimizing the extension');
    await executor.execProGuard(org, processStep);

    // Delete the old non-optimized JAR...
    artJar.deleteSync();

    // ...and rename the optimized JAR with old JAR's name
    File(p.join(p.dirname(artJar.path), 'ART.opt.jar'))
      ..copySync(artJar.path)
      ..deleteSync(recursive: true);
  }

  /// Convert generated extension JAR file from previous step into DEX
  /// bytecode.
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

    final store = ErrWarnStore();
    var warn = '';

    if (store.getWarnings > 0) {
      warn += '[\u001b[33m'; // yellow
      warn += store.getWarnings > 1
          ? '${store.getWarnings} warnings'
          : '${store.getWarnings} warning';
      warn += '\u001b[0m]'; // reset
    }

    Logger.logCustom(
        'Build successful ${BuildUtils.getTimeDifference(_startTime, DateTime.now())} $warn',
        prefix: '\n• ',
        prefixFG: ConsoleColor.brightGreen);
    exit(0);
  }
}
