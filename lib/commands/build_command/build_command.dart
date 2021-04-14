import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dart_console/dart_console.dart';
import 'package:hive/hive.dart';
import 'package:path/path.dart' as p;
import 'package:process_run/which.dart';
import 'package:rush_cli/commands/build_command/ant_args.dart';
import 'package:rush_cli/commands/build_command/helper.dart';
import 'package:rush_cli/javac_errors/err_data.dart';

import 'package:rush_cli/mixins/app_data_dir_mixin.dart';
import 'package:rush_cli/mixins/copy_mixin.dart';
import 'package:rush_cli/mixins/is_yaml_valid.dart';
import 'package:rush_prompt/rush_prompt.dart';
import 'package:yaml/yaml.dart';

class BuildCommand extends Command with AppDataMixin, CopyMixin {
  final String _cd;

  BuildCommand(this._cd) {
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
        prefix: '•',
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
        ..finish('Failed', ConsoleColor.red);
      Logger.log('Build failed',
          color: ConsoleColor.brightWhite,
          prefix: '\n•',
          prefixFG: ConsoleColor.brightRed);
      exit(1);
    }

    // Load rush.yml in a Dart understandable way.
    YamlMap? loadedYml;
    try {
      loadedYml = loadYaml(rushYml.readAsStringSync());
    } catch (e) {
      valStep
        ..logErr('Metadata file (rush.yml) is invalid')
        ..logErr(e.toString(), addPrefix: false, addSpace: true)
        ..finish('Failed', ConsoleColor.red);
      Logger.log('Build failed',
          color: ConsoleColor.brightWhite,
          prefix: '\n•',
          prefixFG: ConsoleColor.brightRed);
      exit(1);
    }

    if (!IsYamlValid.check(rushYml, loadedYml!)) {
      valStep
        ..logErr(
            'One or more necessary fields are missing in the metadata file (rush.yml)')
        ..finish('Failed', ConsoleColor.red);
      Logger.log('Build failed',
          color: ConsoleColor.brightWhite,
          prefix: '\n•',
          prefixFG: ConsoleColor.brightRed);
      exit(1);
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
        ..finish('Failed', ConsoleColor.red);
      Logger.log('Build failed',
          color: ConsoleColor.brightWhite,
          prefix: '\n•',
          prefixFG: ConsoleColor.brightRed);
      exit(1);
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
    valStep.finish('Done', ConsoleColor.cyan);

    final dataDir = AppDataMixin.dataStorageDir();

    Hive.init(p.join(_cd, '.rush'));
    final extBox = await Hive.openBox('data');

    // This is done in case the user deletes the .rush directory.
    if (!extBox.containsKey('version')) {
      await extBox.put('version', 1);
    } else if (!extBox.containsKey('rushYmlLastMod')) {
      await extBox.put('rushYmlLastMod', rushYml.lastModifiedSync());
    } else if (!extBox.containsKey('srcDirLastMod')) {
      await extBox.put('srcDirLastMod', rushYml.lastModifiedSync());
    } else if (!extBox.containsKey('org')
        // ||
        //     extBox.get('org') != _getPackage(loadedYml, p.join(_cd, 'src'))
        ) {
      await extBox.put(
          'org', Helper.getPackage(loadedYml['name'], p.join(_cd, 'src')));
    }

    var isYmlMod =
        rushYml.lastModifiedSync().isAfter(extBox.get('rushYmlLastMod'));
    var isSrcDirMod = false;

    Directory(p.join(_cd, 'src')).listSync(recursive: true).forEach((el) {
      if (el is File) {
        final mod = el.lastModifiedSync();
        if (mod.isAfter(extBox.get('srcDirLastMod'))) {
          isSrcDirMod = true;
          extBox.put('srcDirLastMod', mod);
        }
      }
    });

    var areFilesModified = isYmlMod || isSrcDirMod;

    if (areFilesModified) {
      Helper.cleanDir(p.join(dataDir!, 'workspaces', extBox.get('org')));
    }

    // Update version number stored in box if it doesn't matches with the
    // version from rush.yml
    final extVerYml = loadedYml['version']['number'];
    final extVerBox = await extBox.get('version');
    if (extVerYml != 'auto' && extVerYml != extVerBox) {
      await extBox.put('version', extVerYml);
    }

    // Increment version number if this is a production build.
    final isProd = argResults!['release'];
    if (isProd && extVerYml == 'auto') {
      var version = extVerBox + 1;
      await extBox.put('version', version);
      Helper.cleanDir(p.join(dataDir!, 'workspaces', extBox.get('org')));
      areFilesModified = true;
    }

    var optimize = loadedYml['release']?['optimize'] ?? false;
    if (argResults!['no-optimize']) {
      optimize = false;
    } else if (argResults!['optimize']) {
      optimize = true;
    }

    // Args for spawning the Apache Ant process
    final args = AntArgs(
        dataDir,
        _cd,
        extBox.get('org'),
        extBox.get('version').toString(),
        loadedYml['name'],
        argResults!['support-lib'],
        optimize);

    final pathToAntEx = p.join(scriptPath.split('bin').first, 'tools',
        'apache-ant-1.10.9', 'bin', 'ant');

    await _compile(pathToAntEx, args, optimize);
  }

  /// Compiles all the Java files located at _cd/src.
  Future<void> _compile(String antPath, AntArgs args, bool optimize) async {
    final compStep = BuildStep('Compiling Java files')..init();

    final mainExtFile = File(
        p.joinAll([_cd, 'src', ...args.org!.split('.'), args.name! + '.java']));
    if (!mainExtFile.existsSync()) {
      compStep
        ..logErr(
            'The extension\'s main Java file (${args.name!}.java) not found.',
            addSpace: true)
        ..finish('Failed', ConsoleColor.red);
      Logger.log('Build failed',
          color: ConsoleColor.brightWhite,
          prefix: '\n•',
          prefixFG: ConsoleColor.brightRed);
      exit(1);
    }

    var count = 0;
    var errCount = 0;
    var warnCount = 0;

    // Spawn the javac process
    final javacStream = Process.start(
            antPath, args.toList('javac') as List<String>,
            runInShell: true)
        .asStream()
        .asBroadcastStream();

    await for (final process in javacStream) {
      final stdoutStream = process.stdout.asBroadcastStream();

      await for (final data in stdoutStream) {
        // A list of output messages.
        final formatted = Helper.format(data);

        // Go through each of the formatted message, and check if it's the start
        // of error, part of error, or a warning.
        for (final out in formatted) {
          final lines = ErrData.getNoOfLines(out);

          // If lines is the not null then it means that out is in fact the first
          // line of the error.
          if (lines != null) {
            count = lines - 1;

            final msg = 'src' + out.split('src').last;
            compStep.logErr(msg, addSpace: true);

            errCount++;
          } else if (count > 0) {
            // If count is greater than 0, then it means that out is remaining part
            // of the previously identified error.

            count--;
            compStep.logErr(out, addPrefix: false);
          } else if (out.contains('ERR ')) {
            // If out contains 'ERR' then it means that this error is from
            // the annotaion processor. All errors coming from annotation processor
            // are one liner, so, no need for any over head, we can directly print
            // them.

            final msg = out.split('ERR ').last;
            compStep.logErr(msg, addSpace: true);

            errCount++;
          } else if (out.contains('error: ')) {
            // If this condition is reached then it means this of error *maybe*
            // doesn't fall in any of the javac err categories.
            // So, we increase the count by 2 assuming this error is a 3-liner
            // since most javac errors are 3-liner.

            count += 4;
            final msg = 'src' + out.split('src').last;
            compStep.logErr(msg, addSpace: true);

            errCount++;
          } else if (out.contains('warning:') &&
              !out.contains(
                  'The following options were not recognized by any processor:')) {
            final msg = out.replaceAll('warning: ', '').trim();
            compStep.logWarn(msg, addSpace: true);
            
            warnCount++;
          } else if (argResults!['extended-output'] &&
              !out.startsWith('Buildfile:')) {
            compStep.log(out.trimRight(), ConsoleColor.brightWhite);
          }
        }
      }
    }

    if (warnCount > 0) {
      compStep.log('Total warning(s): $warnCount', ConsoleColor.yellow,
          addSpace: true);
    }
    if (errCount > 0) {
      compStep
        ..log('Total error(s): $errCount', ConsoleColor.red,
            addSpace: warnCount <= 0)
        ..finish('Failed', ConsoleColor.red);
      Logger.log('Build failed',
          color: ConsoleColor.brightWhite,
          prefix: '\n•',
          prefixFG: ConsoleColor.brightRed);
      exit(1);
    }
    compStep.finish('Done', ConsoleColor.cyan);
    await _process(antPath, args, optimize);
  }

  /// Further process the extension by generating extension files, adding
  /// libraries and jaring the extension.
  Future<void> _process(String antPath, AntArgs args, bool optimize) async {
    final BuildStep procStep;

    if (optimize) {
      procStep = BuildStep('Optimizing Java bytecode')..init();

      final rules = File(p.join(_cd, 'src', 'proguard-rules.pro'));
      if (!rules.existsSync()) {
        procStep.logWarn(
            '\'proguard-rules.pro file not found. Your extension won\'t be optimised.',
            addSpace: true);
      }
    } else {
      procStep = BuildStep('Processing extension files')..init();
    }

    var errCount = 0;
    var lastOutLine = '';
    var isExpection = false;

    final processStream = Process.start(
            antPath, args.toList('process') as List<String>,
            runInShell: true)
        .asStream()
        .asBroadcastStream();

    await for (final process in processStream) {
      final stdoutStream = process.stdout.asBroadcastStream();

      await for (final data in stdoutStream) {
        var isFirst = true;

        final formatted = Helper.format(data);

        for (final out in formatted) {
          final totalTimeRegex =
              RegExp(r'Total\s*time:.*', dotAll: true, caseSensitive: true);

          if (!totalTimeRegex.hasMatch(out)) {
            lastOutLine = out;
          }

          if (isExpection) {
            procStep.logErr(' ' * 7 + out.trim(), addPrefix: false);
          }

          if (out.startsWith(
              RegExp(r'\s*Exception in thread', caseSensitive: true))) {
            isExpection = true;
            procStep.logErr(out.trim());
          } else if (out.startsWith('ERR')) {
            procStep.logErr(out.replaceAll('ERR ', ''), addSpace: true);
            errCount++;
          } else if (Helper.isProGuardOutput(out)) {
            var proOut = out.replaceAll('[proguard] ', '').trimRight();

            if (proOut.startsWith(RegExp(r'\sWarning:'))) {
              procStep.logWarn(proOut.replaceAll('Warning: ', ''));
              isFirst = false;
            } else if (proOut.startsWith(RegExp(r'\sNote: '))) {
              proOut = proOut.replaceAll('Note: ', '');
              procStep.log(
                proOut,
                ConsoleColor.brightBlue,
                prefix: 'NOTE',
                prefFG: ConsoleColor.black,
                prefBG: ConsoleColor.brightBlue,
                addSpace: isFirst,
              );
              isFirst = false;
            } else {
              procStep.log(proOut, ConsoleColor.brightWhite);
            }
          } else if (argResults!['extended-output'] &&
              !out.startsWith('Buildfile:')) {
            procStep.log(
              out.trimRight(),
              ConsoleColor.brightWhite,
            );
          }
        }
      }
    }

    if (lastOutLine == 'BUILD FAILED' || isExpection) {
      procStep.finish('Failed', ConsoleColor.red);
      Logger.log('Build failed',
          color: ConsoleColor.brightWhite,
          prefix: '\n•',
          prefixFG: ConsoleColor.brightRed);
      exit(1);
    }

    if (errCount > 0) {
      procStep
        ..log('Total errors: $errCount', ConsoleColor.red)
        ..finish('Failed', ConsoleColor.red);
      Logger.log('Build failed',
          color: ConsoleColor.brightWhite,
          prefix: '\n•',
          prefixFG: ConsoleColor.brightRed);
      exit(1);
    }
    procStep.finish('Done', ConsoleColor.cyan);

    await _dex(antPath, args);
  }

  /// Convert generated extension JAR file from previous step into DEX
  /// bytecode.
  Future<void> _dex(String antPath, AntArgs args) async {
    final dexStep = BuildStep('Converting Java bytecode to DEX bytecode');
    dexStep.init();

    final dexStream = Process.start(antPath, args.toList('dex') as List<String>,
            runInShell: true)
        .asStream()
        .asBroadcastStream();

    var hasGotError = false;

    await for (final process in dexStream) {
      final stdoutStream = process.stdout.asBroadcastStream();

      await for (final data in stdoutStream) {
        final formatted = Helper.format(data);

        for (final out in formatted) {
          if (argResults!['extended-output'] && !out.startsWith('Buildfile:')) {
            dexStep.log(out, ConsoleColor.brightWhite);
          } else {
            if (hasGotError) {
              dexStep.logErr(out, addPrefix: false);
            } else if (out.contains(RegExp(r'error', caseSensitive: false))) {
              hasGotError = true;
              dexStep.logErr(out);
            }
          }
        }
      }
    }

    if (hasGotError) {
      dexStep.finish('Failed', ConsoleColor.red);
      Logger.log('Build failed',
          color: ConsoleColor.brightWhite,
          prefix: '\n•',
          prefixFG: ConsoleColor.brightRed);
      exit(1);
    } else {
      dexStep.finish('Done', ConsoleColor.cyan);
      await _finalize(antPath, args);
    }
  }

  /// Finalize the build.
  Future<void> _finalize(String antPath, AntArgs args) async {
    final finalStep = BuildStep('Finalizing the build');
    finalStep.init();

    final finalStream = Process.start(
            antPath, args.toList('assemble') as List<String>,
            runInShell: true)
        .asStream()
        .asBroadcastStream();

    var hasGotError = false;

    await for (final process in finalStream) {
      final stdoutStream = process.stdout.asBroadcastStream();

      await for (final data in stdoutStream) {
        final formatted = Helper.format(data);

        for (final out in formatted) {
          if (argResults!['extended-output'] && !out.startsWith('Buildfile:')) {
            finalStep.log(out, ConsoleColor.brightWhite);
          } else {
            if (hasGotError) {
              finalStep.logErr(out);
            } else if (out.contains(RegExp(r'error', caseSensitive: false))) {
              hasGotError = true;
              finalStep.logErr(out);
            }
          }
        }
      }
    }

    if (hasGotError) {
      finalStep.finish('Failed', ConsoleColor.red);
      Logger.log('Build failed',
          color: ConsoleColor.brightWhite,
          prefix: '\n•',
          prefixFG: ConsoleColor.brightRed);
      exit(1);
    } else {
      finalStep.finish('Done', ConsoleColor.cyan);
      Logger.log('Build successful',
          color: ConsoleColor.brightWhite,
          prefix: '\n•',
          prefixFG: ConsoleColor.brightGreen);
      exit(0);
    }
  }
}
