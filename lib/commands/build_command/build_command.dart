import 'dart:io' show File, Directory, exit;

import 'package:archive/archive_io.dart';
import 'package:args/command_runner.dart';
import 'package:dart_console/dart_console.dart';
import 'package:hive/hive.dart';
import 'package:path/path.dart' as p;
import 'package:rush_cli/generator/generator.dart';
import 'package:rush_cli/helpers/check_yaml.dart';
import 'package:rush_cli/helpers/utils.dart';
import 'package:rush_cli/java/javac.dart';
import 'package:rush_cli/java/jar_runner.dart';

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
    {
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
    Utils().copyDevDeps(_dataDir, _cd);

    await _updateBoxValues(dataBox, loadedYml);

    var isYmlMod =
        rushYml.lastModifiedSync().isAfter(await dataBox.get('rushYmlLastMod'));

    var isManifestMod = manifestFile
        .lastModifiedSync()
        .isAfter(await dataBox.get('manifestLastMod'));

    if (isYmlMod || isManifestMod) {
      Utils.cleanDir(p.join(_dataDir, 'workspaces', dataBox.get('org')));

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

      Utils.cleanDir(p.join(_dataDir, 'workspaces', dataBox.get('org')));
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

    await _compile(dataBox, optimize);
  }

  Future<void> _compile(Box dataBox, bool optimize) async {
    final compStep = BuildStep('Compiling Java files')..init();
    final javac = Javac(_cd, _dataDir);

    await javac.compile(
      CompileType.build,
      compStep,
      dataBox: dataBox,
      onDone: () async {
        _process(
            await dataBox.get('org'), optimize, argResults!['support-lib']);
      },
      onError: () {
        Utils.printFailMsg(Utils.getTimeDifference(startTime, DateTime.now()));
        exit(1);
      },
    );
  }

  /// Further process the extension by generating extension files, adding
  /// libraries and jaring the extension.
  void _process(String org, bool optimize, bool dejet) {
    final BuildStep step;
    final rulesPro = File(p.join(_cd, 'src', 'proguard-rules.pro'));

    if (optimize && rulesPro.existsSync()) {
      step = BuildStep('Optimizing the extension')..init();
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

    _jarExtension(
      org,
      step,
      optimize,
      dejet,
      onSuccess: (String jarPath) async {
        final jar = File(jarPath);

        if (jar.existsSync()) {
          final destDir = Directory(
              p.join(_dataDir, 'workspaces', org, 'raw', 'x', org, 'files'))
            ..createSync(recursive: true);

          jar.copySync(p.join(destDir.path, 'AndroidRuntime.jar'));

          // De-jetify the extension
          if (dejet) {
            _dejetify(
              org,
              step,
              onSuccess: (bool needDejet) {
                if (!needDejet) {
                  // Delete the raw/sup directory so that support version of
                  // the extension isn't generated.
                  Directory(p.join(_dataDir, 'workspaces', org, 'raw', 'sup'))
                      .deleteSync(recursive: true);

                  step
                    ..logWarn('No references to androidx.* were found.',
                        addSpace: true)
                    ..logWarn(
                        ' ' * 5 +
                            'You don\'t need to create a support library version of the extension.',
                        addPrefix: false)
                    ..finishOk('Done');
                  _dex(org, false);
                } else {
                  step.finishOk('Done');
                  _dex(org, true);
                }
              },
              onError: () {
                step.finishNotOk('Failed');
                Utils.printFailMsg(
                    Utils.getTimeDifference(startTime, DateTime.now()));
                exit(1);
              },
            );
          } else {
            step.finishOk('Done');
            _dex(org, false);
          }
        } else {
          step
            ..logErr('File not found: ' + jar.path)
            ..finishNotOk('Failed');

          Utils.printFailMsg(
              Utils.getTimeDifference(startTime, DateTime.now()));
          exit(1);
        }
      },
    );
  }

  /// JAR the compiled class files and third-party dependencies into a
  /// single JAR.
  void _jarExtension(
      String org, BuildStep processStep, bool optimize, bool dejet,
      {required Function onSuccess}) {
    final rawClassesDir =
        Directory(p.join(_dataDir, 'workspaces', org, 'raw-classes', org));

    // Run the jar command-line tool. It is used to generate a JAR.
    final runner = JarRunner(_cd, _dataDir);
    runner.run(
      JarType.jar,
      org,
      processStep,
      onSuccess: () {
        if (optimize) {
          // Optimize the extension
          _optimize(
            org,
            processStep,
            onSuccess: () {
              // Delete the old non-optimized JAR...
              final oldJar = File(rawClassesDir.path + '.jar')..deleteSync();

              // ...and rename the optimized JAR with old JAR's name
              File(rawClassesDir.path + '_pg.jar')
                ..copySync(oldJar.path)
                ..deleteSync(recursive: true);

              onSuccess(oldJar.path);
            },
            onError: () {
              processStep.finishNotOk('Failed');
              Utils.printFailMsg(
                  Utils.getTimeDifference(startTime, DateTime.now()));
              exit(1);
            },
          );
        } else {
          onSuccess(rawClassesDir.path + '.jar');
        }
      },
      onError: () {
        processStep.finishNotOk('Failed');
        Utils.printFailMsg(Utils.getTimeDifference(startTime, DateTime.now()));
        exit(1);
      },
    );
  }

  /// ProGuards the extension.
  void _optimize(String org, BuildStep processStep,
      {required Function onSuccess, required Function onError}) {
    final runner = JarRunner(_cd, _dataDir);
    runner.run(
      JarType.proguard,
      org,
      processStep,
      onSuccess: onSuccess,
      onError: onError,
    );
  }

  void _dejetify(String org, BuildStep processStep,
      {required Function onSuccess, required Function onError}) {
    final runner = JarRunner(_cd, _dataDir);
    runner.run(
      JarType.jetifier,
      org,
      processStep,
      onSuccess: onSuccess,
      onError: onError,
    );
  }

  /// Convert generated extension JAR file from previous step into DEX
  /// bytecode.
  void _dex(String org, bool dejet) {
    final step = BuildStep('Converting Java bytecode to DEX bytecode')..init();

    final runner = JarRunner(_cd, _dataDir);
    runner.run(
      JarType.d8,
      org,
      step,
      onSuccess: () {
        if (dejet) {
          runner.run(
            JarType.d8sup,
            org,
            step,
            onSuccess: () {
              step.finishOk('Done');
              _assemble(org);
            },
            onError: () {
              step.finishNotOk('Failed');
              Utils.printFailMsg(
                  Utils.getTimeDifference(startTime, DateTime.now()));
              exit(1);
            },
          );
        } else {
          step.finishOk('Done');
          _assemble(org);
        }
      },
      onError: () {
        step.finishNotOk('Failed');
        Utils.printFailMsg(Utils.getTimeDifference(startTime, DateTime.now()));
        exit(1);
      },
    );
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
        'Build successful in ${Utils.getTimeDifference(startTime, DateTime.now())}',
        color: ConsoleColor.brightWhite,
        prefix: '\n• ',
        prefixFG: ConsoleColor.brightGreen);
    exit(0);
  }

  Future<void> _updateBoxValues(Box box, YamlMap yaml) async {
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
