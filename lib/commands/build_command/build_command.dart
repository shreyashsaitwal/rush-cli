import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:args/command_runner.dart';
import 'package:dart_console/dart_console.dart';
import 'package:hive/hive.dart';
import 'package:path/path.dart' as p;
import 'package:process_run/which.dart';
import 'package:rush_cli/helpers/is_yaml_valid.dart';
import 'package:rush_cli/helpers/utils.dart';
import 'package:rush_cli/java/javac.dart';
import 'package:rush_cli/java/jar_runner.dart';

import 'package:rush_prompt/rush_prompt.dart';
import 'package:yaml/yaml.dart';

class BuildCommand extends Command {
  final String _cd;
  final String _dataDir;

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
      ..addFlag('no-optimize', negatable: false, defaultsTo: false)
      ..addFlag('extended-output', abbr: 'x', hide: true, defaultsTo: false);
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

    final scriptPath = whichSync('rush');

    if (scriptPath == p.join(_cd, 'rush')) {
      Logger.logErr(
          'Uh, oh! Looks like you\'re using an unsupported terminal.\nPlease try using another terminal.',
          exitCode: 64);
    }

    if (await which('java') == null) {
      Logger.logErr(
          'Uh, oh! Looks like you\'re don\'t have JDK installed on your system.\nPlease download and install JDK version 1.8 or above.',
          exitCode: 64);
    }

    Logger.log('Build initialized\n',
        color: ConsoleColor.brightWhite,
        prefix: '• ',
        prefixFG: ConsoleColor.yellow);

    Helper().copyDevDeps(scriptPath!, _cd);

    final valStep = BuildStep('Validating project files');
    valStep.init();

    File? rushYml;
    // Check if rush.yml exists and is valid
    if (File(p.join(_cd, 'rush.yaml')).existsSync()) {
      rushYml = File(p.join(_cd, 'rush.yaml'));
    } else if (File(p.join(_cd, 'rush.yml')).existsSync()) {
      rushYml = File(p.join(_cd, 'rush.yml'));
    } else {
      valStep
        ..logErr('Metadata file (rush.yml) not found')
        ..finishNotOk('Failed');
      _failBuild();
    }

    // Load rush.yml in a Dart understandable way.
    YamlMap? loadedYml;
    try {
      loadedYml = loadYaml(rushYml!.readAsStringSync());
    } catch (e) {
      valStep
        ..logErr('Metadata file (rush.yml) is invalid')
        ..logErr(e.toString(), addPrefix: false, addSpace: true)
        ..finishNotOk('Failed');
      _failBuild();
    }

    if (!IsYamlValid.check(rushYml, loadedYml!)) {
      valStep
        ..logErr(
            'One or more necessary fields are missing in the metadata file (rush.yml)')
        ..finishNotOk('Failed');
      _failBuild();
    } else {
      valStep.log(
        'Metadata file (rush.yml)',
        ConsoleColor.brightWhite,
        addSpace: true,
        prefix: 'OK',
        prefBG: ConsoleColor.brightGreen,
        prefFG: ConsoleColor.black,
      );
    }

    final manifestFile = File(p.join(_cd, 'src', 'AndroidManifest.xml'));
    if (!manifestFile.existsSync()) {
      valStep
        ..logErr('AndroidManifest.xml not found')
        ..finishNotOk('Failed');
      _failBuild();
    } else {
      valStep.log(
        'AndroidManifest.xml file',
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
    if (!dataBox.containsKey('name')) {
      await dataBox.put('name', loadedYml['name']! as String);
    } else if (!dataBox.containsKey('version')) {
      await dataBox.put('version', 1);
    } else if (!dataBox.containsKey('rushYmlLastMod')) {
      await dataBox.put('rushYmlLastMod', rushYml!.lastModifiedSync());
    } else if (!dataBox.containsKey('srcDirLastMod')) {
      await dataBox.put('srcDirLastMod', rushYml!.lastModifiedSync());
    } else if (!dataBox.containsKey('org')) {
      await dataBox.put(
          'org', Helper.getPackage(loadedYml['name'], p.join(_cd, 'src')));
    }

    var isYmlMod = rushYml!
        .lastModifiedSync()
        .isAfter(await dataBox.get('rushYmlLastMod'));
    var isSrcDirMod = false;

    Directory(p.join(_cd, 'src')).listSync(recursive: true).forEach((el) {
      if (el is File) {
        final mod = el.lastModifiedSync();
        if (mod.isAfter(dataBox.get('srcDirLastMod'))) {
          isSrcDirMod = true;
          dataBox.put('srcDirLastMod', mod);
        }
      }
    });

    var areFilesModified = isYmlMod || isSrcDirMod;

    if (areFilesModified) {
      Helper.cleanDir(p.join(_dataDir, 'workspaces', dataBox.get('org')));
    }

    // Update version number stored in box if it doesn't matches with the
    // version from rush.yml
    final extVerYml = loadedYml['version']['number'];
    final extVerBox = await dataBox.get('version');
    if (extVerYml != 'auto' && extVerYml != extVerBox) {
      await dataBox.put('version', extVerYml);
    }

    // Increment version number if this is a production build.
    final isProd = argResults!['release'];
    if (isProd && extVerYml == 'auto') {
      var version = extVerBox + 1;
      await dataBox.put('version', version);
      Helper.cleanDir(p.join(_dataDir, 'workspaces', dataBox.get('org')));
      areFilesModified = true;
    }

    final optimize;
    if (argResults!['optimize']) {
      optimize = true;
    } else if (isProd) {
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
        _failBuild();
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

    // Run the rush annotation processor
    final runner = JarRunner(_cd, _dataDir);
    runner.run(
      JarType.processor,
      org,
      step,
      onSuccess: () {
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
                      Directory(
                              p.join(_dataDir, 'workspaces', org, 'raw', 'sup'))
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
                    _failBuild();
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

              _failBuild();
            }
          },
        );
      },
      onError: () {
        step.finishNotOk('Failed');
        _failBuild();
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

    // Unjar dependencies
    for (final entity in rawClassesDir.listSync()) {
      if (entity is File && p.extension(entity.path) == '.jar') {
        Helper.extractJar(entity.path, p.dirname(entity.path));
      }
    }

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
              _failBuild();
            },
          );
        } else {
          onSuccess(rawClassesDir.path + '.jar');
        }
      },
      onError: () {
        processStep.finishNotOk('Failed');
        _failBuild();
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
              _failBuild();
            },
          );
        } else {
          step.finishOk('Done');
          _assemble(org);
        }
      },
      onError: () {
        step.finishNotOk('Failed');
        _failBuild();
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

    Logger.log('Build successful',
        color: ConsoleColor.brightWhite,
        prefix: '\n• ',
        prefixFG: ConsoleColor.brightGreen);
    exit(0);
  }

  void _failBuild() {
    Logger.log('Build failed',
        color: ConsoleColor.brightWhite,
        prefix: '\n• ',
        prefixFG: ConsoleColor.brightRed);
    exit(1);
  }
}
