import 'dart:io' show File, Directory, exit;

import 'package:checked_yaml/checked_yaml.dart';
import 'package:path/path.dart' as p;
import 'package:archive/archive_io.dart';
import 'package:args/command_runner.dart';
import 'package:dart_console/dart_console.dart';
import 'package:hive/hive.dart';
import 'package:rush_cli/commands/build_command/helpers/generator.dart';
import 'package:rush_cli/commands/build_command/helpers/executor.dart';
import 'package:rush_cli/commands/build_command/models/rush_yaml.dart';

import 'package:rush_prompt/rush_prompt.dart';

import 'helpers/build_utils.dart';
import 'helpers/compiler.dart';

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
      ..setForegroundColor(ConsoleColor.brightWhite)
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
      ..setForegroundColor(ConsoleColor.brightWhite)
      ..writeLine(' Available flags:')
      ..setForegroundColor(ConsoleColor.yellow)
      ..write('   -r, --release')
      ..setForegroundColor(ConsoleColor.brightWhite)
      ..writeLine(' ' * 9 + 'Marks this build as a release build.')
      ..setForegroundColor(ConsoleColor.yellow)
      ..write('   -s, --support-lib')
      ..setForegroundColor(ConsoleColor.brightWhite)
      ..writeLine(' ' * 5 +
          'Generates two flavors of extensions, one that uses AndroidX libraries, and other that '
              'uses support libraries.')
      ..setForegroundColor(ConsoleColor.yellow)
      ..write('   -o, --[no-]optimize')
      ..setForegroundColor(ConsoleColor.brightWhite)
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

    Logger.log('Build initialized\n',
        color: ConsoleColor.brightWhite,
        prefix: '• ',
        prefixFG: ConsoleColor.yellow);

    final valStep = BuildStep('Checking project files')..init();

    final manifestFile = File(p.join(_cd, 'src', 'AndroidManifest.xml'));
    if (!manifestFile.existsSync()) {
      valStep
        ..logErr('AndroidManifest.xml not found')
        ..finishNotOk();

      BuildUtils.printFailMsg(
          BuildUtils.getTimeDifference(_startTime, DateTime.now()));
      exit(1);
    }

    valStep.log(
      'AndroidManifest.xml file found',
      ConsoleColor.brightWhite,
      addSpace: true,
      prefix: 'OK',
      prefBG: ConsoleColor.brightGreen,
      prefFG: ConsoleColor.black,
    );

    File yamlFile;
    try {
      yamlFile = BuildUtils.getRushYaml(_cd);
    } catch (_) {
      valStep
        ..logErr('Metadata file (rush.yml) not found')
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
        (json) => RushYaml.fromJson(json!),
        sourceUrl: Uri.tryParse(
            'https://raw.githubusercontent.com/shreyashsaitwal/rush-cli/main/schema/rush.json'),
      );

      await BuildUtils.ensureBoxValues(_cd, dataBox, rushYaml);
    } on ParsedYamlException catch (e) {
      valStep.logErr(
          'The following error occurred while validating metadata file (rush.yml):',
          addSpace: true);

      e.message.split('\n').forEach((element) {
        valStep.logErr(' ' * 4 + element, addPrefix: false);
      });

      valStep.finishNotOk();
      BuildUtils.printFailMsg(
          BuildUtils.getTimeDifference(_startTime, DateTime.now()));
      exit(2);
    } catch (e) {
      valStep.logErr(
          'The following error occurred while validating metadata file (rush.yml):',
          addSpace: true);

      if (e.toString().contains('\n')) {
        e.toString().split('\n').forEach((element) {
          valStep.logErr(' ' * 4 + element, addPrefix: false);
        });
      } else {
        valStep.logErr(' ' * 4 + e.toString(), addPrefix: false);
      }

      valStep.finishNotOk();
      BuildUtils.printFailMsg(
          BuildUtils.getTimeDifference(_startTime, DateTime.now()));
      exit(2);
    }

    valStep
      ..log(
        'Metadata file (rush.yml) found',
        ConsoleColor.brightWhite,
        addSpace: true,
        prefix: 'OK',
        prefBG: ConsoleColor.brightGreen,
        prefFG: ConsoleColor.black,
      )
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

    final optimize = BuildUtils.needsOptimization(
        isRelease, argResults!['optimize'], rushYaml);

    await _compile(dataBox, optimize, rushYaml.kotlin?.enable ?? false);
  }

  /// Compiles extension's source files
  Future<void> _compile(Box dataBox, bool optimize, bool enableKt) async {
    final step = BuildStep('Compiling source files')..init();
    final compiler = Compiler(_cd, _dataDir);

    final srcFiles = Directory(p.join(_cd, 'src'))
        .listSync(recursive: true)
        .whereType<File>();

    final hasJavaFiles =
        srcFiles.any((file) => p.extension(file.path) == '.java');
    final hasKtFiles = srcFiles.any((file) => p.extension(file.path) == '.kt');

    try {
      if (hasKtFiles) {
        if (!enableKt) {
          step
            ..logErr('Kotlin files detected. Please enable Kotlin in rush.yml.')
            ..finishNotOk();
          exit(1);
        }

        await compiler.compileKt(dataBox, step);
      }

      if (hasJavaFiles) {
        await compiler.compileJava(dataBox, step);
      }
    } catch (e) {
      step.finishNotOk();
      BuildUtils.printFailMsg(
          BuildUtils.getTimeDifference(_startTime, DateTime.now()));
      exit(1);
    }

    step.finishOk();
    await _process(
        await dataBox.get('org'), optimize, argResults!['support-lib']);
  }

  /// Further process the extension by generating extension files, adding
  /// libraries and jaring the extension.
  Future<void> _process(String org, bool optimize, bool deJet) async {
    final BuildStep step;
    final rulesPro = File(p.join(_cd, 'src', 'proguard-rules.pro'));

    if (optimize && rulesPro.existsSync()) {
      step = BuildStep('Processing and optimizing the extension')..init();
    } else {
      step = BuildStep('Processing the extension')..init();
      if (!rulesPro.existsSync() && optimize) {
        step.logWarn(
            'Unable to find \'proguard-rules.pro\' in \'src\' directory.',
            addSpace: true);
        optimize = false;
      }
    }

    // Generate the extension files
    final generator = Generator(_cd, _dataDir);
    generator.generate(org);

    final executor = Executor(_cd, _dataDir);

    // Create a JAR containing the contents of extension's dependencies and
    // compiled source files
    final extJar = await _jarExtension(org, step, optimize);

    if (extJar.existsSync()) {
      final destDir = Directory(
          p.join(_dataDir, 'workspaces', org, 'raw', 'x', org, 'files'))
        ..createSync(recursive: true);

      extJar.copySync(p.join(destDir.path, 'AndroidRuntime.jar'));
    } else {
      step
        ..logErr('File not found: ' + extJar.path)
        ..finishNotOk();

      BuildUtils.printFailMsg(
          BuildUtils.getTimeDifference(_startTime, DateTime.now()));
      exit(1);
    }

    var needDeJet = deJet;
    if (deJet) {
      try {
        needDeJet = await executor.execJetifier(org, step);
      } catch (e) {
        step.finishNotOk();

        BuildUtils.printFailMsg(
            BuildUtils.getTimeDifference(_startTime, DateTime.now()));

        exit(1);
      }

      if (!needDeJet && deJet) {
        // Delete the raw/sup directory so that support version of
        // the extension isn't generated.
        Directory(p.join(_dataDir, 'workspaces', org, 'raw', 'sup'))
            .deleteSync(recursive: true);

        step.logWarn(
            'No references to AndroidX packages were found. You don\'t need to pass the `-s` flag for now.',
            addSpace: true);
      }
    }

    step.finishOk();
    await _dex(org, needDeJet);
  }

  /// JAR the compiled class files and third-party dependencies into a
  /// single JAR.
  Future<File> _jarExtension(
      String org, BuildStep processStep, bool optimize) async {
    final classesDir =
        Directory(p.join(_dataDir, 'workspaces', org, 'classes'));

    final extJar =
        File(p.join(classesDir.path, 'art.jar')); // ART -> Android Runtime

    final zipEncoder = ZipFileEncoder()..open(extJar.path);

    classesDir.listSync(recursive: true)
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

    for (final entity in classesDir.listSync()) {
      if (entity is File) {
        if (p.extension(entity.path) != '.jar') {
          zipEncoder.addFile(entity);
        }
      } else if (entity is Directory) {
        zipEncoder.addDirectory(entity);
      }
    }

    zipEncoder.close();

    final executor = Executor(_cd, _dataDir);
    try {
      // Run ProGuard if the extension is supposed to be optimized
      if (optimize) {
        await executor.execProGuard(org, processStep);

        // Delete the old non-optimized JAR...
        extJar.deleteSync();

        // ...and rename the optimized JAR with old JAR's name
        File(p.join(classesDir.path, 'art_opt.jar'))
          ..copySync(extJar.path)
          ..deleteSync(recursive: true);
      }
    } catch (e) {
      processStep.finishNotOk();
      BuildUtils.printFailMsg(
          BuildUtils.getTimeDifference(_startTime, DateTime.now()));
      exit(1);
    }

    return extJar;
  }

  /// Convert generated extension JAR file from previous step into DEX
  /// bytecode.
  Future<void> _dex(String org, bool deJet) async {
    final step = BuildStep('Generating DEX bytecode')..init();

    final executor = Executor(_cd, _dataDir);

    try {
      if (deJet) {
        await Future.wait([
          executor.execD8(org, step, true),
          executor.execD8(org, step, false),
        ]);
      } else {
        await executor.execD8(org, step, false);
      }
    } catch (e) {
      step.finishNotOk();
      BuildUtils.printFailMsg(
          BuildUtils.getTimeDifference(_startTime, DateTime.now()));
      exit(1);
    }

    step.finishOk();
    _assemble(org);
  }

  /// Finalize the build.
  void _assemble(String org) {
    final step = BuildStep('Finalizing the build')..init();

    final rawDirX = Directory(p.join(_dataDir, 'workspaces', org, 'raw', 'x'));
    final rawDirSup =
        Directory(p.join(_dataDir, 'workspaces', org, 'raw', 'sup'));

    final outputDir = Directory(p.join(_cd, 'out'))
      ..createSync(recursive: true);

    final zipEncoder = ZipFileEncoder();
    zipEncoder.zipDirectory(rawDirX,
        filename: p.join(outputDir.path, '$org.aix'));

    if (rawDirSup.existsSync()) {
      zipEncoder.zipDirectory(rawDirSup,
          filename: p.join(outputDir.path, '$org.support.aix'));
    }

    step.finishOk();

    Logger.log(
        'Build successful ${BuildUtils.getTimeDifference(_startTime, DateTime.now())}',
        color: ConsoleColor.brightWhite,
        prefix: '\n• ',
        prefixFG: ConsoleColor.brightGreen);
    exit(0);
  }
}
