import 'dart:io' show File, Directory, exit;

import 'package:archive/archive_io.dart';
import 'package:args/command_runner.dart';
import 'package:dart_console/dart_console.dart';
import 'package:hive/hive.dart';
import 'package:path/path.dart' as p;
import 'package:rush_cli/generator/generator.dart';
import 'package:rush_cli/helpers/check_yaml.dart';
import 'package:rush_cli/helpers/utils.dart';
import 'package:rush_cli/java/compiler.dart';
import 'package:rush_cli/java/cmd_runner.dart';

import 'package:rush_prompt/rush_prompt.dart';
import 'package:yaml/yaml.dart';

class BuildCommand extends Command {
  final String _cd;
  final String _dataDir;

  late final startTime;

  BuildCommand(this._cd, this._dataDir) {
    argParser
      ..addFlag('release',
          abbr: 'r',
          defaultsTo: false,
          help:
              'Marks this build as a release build, and hence, increments the version number of the extension by 1.')
      ..addFlag('support-lib',
          abbr: 's',
          defaultsTo: false,
          help:
              'Generates two flavors of extensions, one that uses AndroidX libraries, and other that uses support libraries. The later is supposed to be used with builders that haven\'t yet migrated to AndroidX.')
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
      ..writeLine(' ' * 9 +
          'Marks this build as a release build, which results in the version number being incremented by one.')
      ..setForegroundColor(ConsoleColor.yellow)
      ..write('   -s, --support-lib')
      ..setForegroundColor(ConsoleColor.brightWhite)
      ..writeLine(' ' * 5 +
          'Generates two flavors of extensions, one that uses AndroidX libraries, and other that uses support libraries.')
      ..setForegroundColor(ConsoleColor.yellow)
      ..write('   -o, --[no-]optimize')
      ..setForegroundColor(ConsoleColor.brightWhite)
      ..writeLine(' ' * 3 +
          'Optimize, obfuscates and shrinks your code with a set of ProGuard rules defined in proguard-rules.pro rules file.')
      ..resetColorAttributes()
      ..writeLine();
  }

  /// Builds the extension in the current directory
  @override
  Future<void> run() async {
    PrintArt();
    startTime = DateTime.now();

    Logger.log('Build initialized\n',
        color: ConsoleColor.brightWhite,
        prefix: '• ',
        prefixFG: ConsoleColor.yellow);

    final valStep = BuildStep('Checking project files');
    valStep.init();

    File rushYml;
    final yml = File(p.join(_cd, 'rush.yml'));
    final yaml = File(p.join(_cd, 'rush.yaml'));

    if (yml.existsSync()) {
      rushYml = yml;
    } else if (yaml.existsSync()) {
      rushYml = yaml;
    } else {
      valStep
        ..logErr('Metadata file (rush.yml) not found')
        ..finishNotOk('Failed');
      Utils.printFailMsg(Utils.getTimeDifference(startTime, DateTime.now()));
      exit(1);
    }

    // Load rush.yml in a Dart understandable way.
    YamlMap loadedYml;
    try {
      loadedYml = loadYaml(rushYml.readAsStringSync());
    } catch (e) {
      valStep
        ..logErr('Metadata file (rush.yml) is invalid')
        ..logErr(e.toString(), addPrefix: false, addSpace: true)
        ..finishNotOk('Failed');
      Utils.printFailMsg(Utils.getTimeDifference(startTime, DateTime.now()));
      exit(1);
    }

    CheckRushYml.check(rushYml, valStep, startTime);
    valStep.log(
      'Metadata file (rush.yml) found',
      ConsoleColor.brightWhite,
      addSpace: true,
      prefix: 'OK',
      prefBG: ConsoleColor.brightGreen,
      prefFG: ConsoleColor.black,
    );

    final manifestFile = File(p.join(_cd, 'src', 'AndroidManifest.xml'));
    if (!manifestFile.existsSync()) {
      valStep
        ..logErr('AndroidManifest.xml not found')
        ..finishNotOk('Failed');

      Utils.printFailMsg(Utils.getTimeDifference(startTime, DateTime.now()));
      exit(1);
    } else {
      valStep.log(
        'AndroidManifest.xml file found',
        ConsoleColor.brightWhite,
        addSpace: true,
        prefix: 'OK',
        prefBG: ConsoleColor.brightGreen,
        prefFG: ConsoleColor.black,
      );
    }
    valStep.finishOk('Done');

    Hive.init(p.join(_cd, '.rush'));
    final dataBox = await Hive.openBox('data');

    // This is done in case the user deletes the .rush directory.
    Utils.copyDevDeps(_dataDir, _cd);

    await _ensureBoxValues(dataBox, loadedYml);

    var isYmlMod =
        rushYml.lastModifiedSync().isAfter(await dataBox.get('rushYmlLastMod'));

    var isManifestMod = manifestFile
        .lastModifiedSync()
        .isAfter(await dataBox.get('manifestLastMod'));

    if (isYmlMod || isManifestMod) {
      Utils.cleanWorkspaceDir(_dataDir, await dataBox.get('org'));

      await Future.wait([
        dataBox.put('rushYmlLastMod', rushYml.lastModifiedSync()),
        dataBox.put('manifestLastMod', manifestFile.lastModifiedSync())
      ]);
    }

    // Increment version number if this is a production build.
    final isRelease = argResults!['release'];
    if (isRelease) {
      final extVerYml = loadedYml['version']['number'];

      if (extVerYml == 'auto') {
        final extVerBox = await dataBox.get('version') ?? 0;
        await dataBox.put('version', extVerBox + 1);
      }

      Utils.cleanWorkspaceDir(_dataDir, await dataBox.get('org'));
    }

    final optimize;
    if (argResults!['optimize']) {
      optimize = true;
    } else if (isRelease) {
      if ((loadedYml['release']?['optimize'] ?? false) &&
          !argResults!['no-optimize']) {
        optimize = true;
      } else {
        optimize = false;
      }
    } else {
      optimize = false;
    }

    await _compile(
        dataBox, optimize, (loadedYml['kotlin']?['enable'] ?? false) as bool);
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
            ..finishNotOk('Failed');
          exit(1);
        }

        await Future.wait([
          compiler.compile(CompileType.buildKt, step, dataBox: dataBox),
          compiler.compile(CompileType.kapt, step, dataBox: dataBox)
        ]);
      }

      if (hasJavaFiles) {
        await compiler.compile(CompileType.buildJ, step, dataBox: dataBox);
      }
    } catch (e) {
      step.finishNotOk('Failed');
      Utils.printFailMsg(Utils.getTimeDifference(startTime, DateTime.now()));
      exit(1);
    }

    step.finishOk('Done');
    await _process(
        await dataBox.get('org'), optimize, argResults!['support-lib']);
  }

  /// Further process the extension by generating extension files, adding
  /// libraries and jaring the extension.
  Future<void> _process(String org, bool optimize, bool dejet) async {
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

    final runner = CmdRunner(_cd, _dataDir);

    // Create a JAR containing the contents of extension's dependencies and
    // compiled source files
    final extJar = await _jarExtension(org, step, optimize, dejet);

    if (extJar.existsSync()) {
      final destDir = Directory(
          p.join(_dataDir, 'workspaces', org, 'raw', 'x', org, 'files'))
        ..createSync(recursive: true);

      extJar.copySync(p.join(destDir.path, 'AndroidRuntime.jar'));
    } else {
      step
        ..logErr('File not found: ' + extJar.path)
        ..finishNotOk('Failed');

      Utils.printFailMsg(Utils.getTimeDifference(startTime, DateTime.now()));
      exit(1);
    }

    var needDejet = dejet;
    if (dejet) {
      try {
        await runner.run(CmdType.jetifier, org, step);
        needDejet = runner.getShouldDejet;
      } catch (e) {
        step.finishNotOk('Failed');
        Utils.printFailMsg(Utils.getTimeDifference(startTime, DateTime.now()));
        exit(1);
      }

      if (!needDejet && dejet) {
        // Delete the raw/sup directory so that support version of
        // the extension isn't generated.
        Directory(p.join(_dataDir, 'workspaces', org, 'raw', 'sup'))
            .deleteSync(recursive: true);

        step.logWarn(
            'No references to AndroidX packages were found. You don\'t need to pass the `-s` flag for now.',
            addSpace: true);
      }
    }

    step.finishOk('Done');
    await _dex(org, needDejet);
  }

  /// JAR the compiled class files and third-party dependencies into a
  /// single JAR.
  Future<File> _jarExtension(
      String org, BuildStep processStep, bool optimize, bool dejet) async {
    final classesDir =
        Directory(p.join(_dataDir, 'workspaces', org, 'classes'));

    final extJar =
        File(p.join(classesDir.path, 'art.jar')); // ART -> Android Runtime

    // Run the jar command-line tool. It is used to generate a JAR.
    final runner = CmdRunner(_cd, _dataDir);
    try {
      await runner.run(CmdType.jar, org, processStep);

      // Run ProGuard if the extension is supposed to be optimized/
      if (optimize) {
        await runner.run(CmdType.proguard, org, processStep);

        // Delete the old non-optimized JAR...
        extJar.deleteSync();

        // ...and rename the optimized JAR with old JAR's name
        File(p.join(classesDir.path, 'art_opt.jar'))
          ..copySync(extJar.path)
          ..deleteSync(recursive: true);
      }
    } catch (e) {
      processStep.finishNotOk('Failed');
      Utils.printFailMsg(Utils.getTimeDifference(startTime, DateTime.now()));
      exit(1);
    }

    return extJar;
  }

  /// Convert generated extension JAR file from previous step into DEX
  /// bytecode.
  Future<void> _dex(String org, bool dejet) async {
    final step = BuildStep('Generating DEX bytecode')..init();

    final runner = CmdRunner(_cd, _dataDir);

    try {
      if (dejet) {
        await Future.wait([
          runner.run(CmdType.d8, org, step),
          runner.run(CmdType.d8sup, org, step),
        ]);
      } else {
        await runner.run(CmdType.d8, org, step);
      }
    } catch (e) {
      step.finishNotOk('Failed');
      Utils.printFailMsg(Utils.getTimeDifference(startTime, DateTime.now()));
      exit(1);
    }

    step.finishOk('Done');
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

    step.finishOk('Done');

    Logger.log(
        'Build successful ${Utils.getTimeDifference(startTime, DateTime.now())}',
        color: ConsoleColor.brightWhite,
        prefix: '\n• ',
        prefixFG: ConsoleColor.brightGreen);
    exit(0);
  }

  /// Ensures that the required data exists in the data box.
  Future<void> _ensureBoxValues(Box box, YamlMap yaml) async {
    final extName = yaml['name'];
    if (!box.containsKey('name') || (await box.get('name')) != extName) {
      await box.put('name', yaml['name']);
    }

    final extOrg = Utils.getPackage(extName, p.join(_cd, 'src'));
    if (!box.containsKey('org') || (await box.get('org')) != extOrg) {
      await box.put('org', extOrg);
    }

    final extVersion = yaml['version']['number'];
    if (!box.containsKey('version')) {
      if (extVersion != 'auto') {
        await box.put('version', extVersion as int);
      } else {
        await box.put('version', 1);
      }
    } else if ((await box.get('version')) != extVersion &&
        extVersion != 'auto') {
      await box.put('version', extVersion as int);
    }

    if (!box.containsKey('rushYmlLastMod') ||
        (await box.get('rushYmlLastMod')) == null) {
      final DateTime lastMod;

      final rushYml = File(p.join(_cd, 'rush.yml'));
      final rushYaml = File(p.join(_cd, 'rush.yaml'));

      if (rushYml.existsSync()) {
        lastMod = rushYml.lastModifiedSync();
      } else {
        lastMod = rushYaml.lastModifiedSync();
      }

      await box.put('rushYmlLastMod', lastMod);
    }

    if (!box.containsKey('manifestLastMod') ||
        (await box.get('manifestLastMod')) == null) {
      final lastMod =
          File(p.join(_cd, 'src', 'AndroidManifest.xml')).lastModifiedSync();

      await box.put('manifestLastMod', lastMod);
    }
  }
}
