import 'dart:io';

import 'package:dart_console/dart_console.dart';
import 'package:hive/hive.dart';
import 'package:path/path.dart' as p;
import 'package:rush_cli/commands/build_command/ant_args.dart';
import 'package:rush_cli/javac_errors/err_data.dart';

import 'package:rush_cli/mixins/app_data_dir_mixin.dart';
import 'package:rush_cli/mixins/copy_mixin.dart';
import 'package:rush_cli/mixins/is_yaml_valid.dart';
import 'package:rush_prompt/rush_prompt.dart';
import 'package:yaml/yaml.dart';

class BuildCommand with AppDataMixin, CopyMixin {
  final String _cd;
  final String _extType;
  final bool _isProd;

  BuildCommand(this._cd, this._extType, this._isProd);

  /// Builds the extension in the current directory
  Future<void> run() async {
    PrintMsg('Build initialized\n', ConsoleColor.brightWhite, '•',
        ConsoleColor.yellow);

    final valStep = BuildStep('Validating project files');
    valStep.init();

    // Check if rush.yml exists and is valid
    File rushYml;
    if (File(p.join(_cd, 'rush.yaml')).existsSync()) {
      rushYml = File(p.join(_cd, 'rush.yaml'));
    } else if (File(p.join(_cd, 'rush.yml')).existsSync()) {
      rushYml = File(p.join(_cd, 'rush.yml'));
    } else {
      valStep
        ..add('Metadata file (rush.yml) not found', ConsoleColor.red)
        ..finish('Failed', ConsoleColor.red);
      PrintMsg('Build failed', ConsoleColor.brightWhite, '\n•',
          ConsoleColor.brightRed);
      exit(1);
    }

    if (!IsYamlValid.check(rushYml)) {
      valStep
        ..add('Metadata file (rush.yml) is invalid', ConsoleColor.red)
        ..finish('Failed', ConsoleColor.red);
      PrintMsg('Build failed', ConsoleColor.brightWhite, '\n•',
          ConsoleColor.brightRed);
      exit(1);
    }

    final manifestFile = File(p.join(_cd, 'src', 'AndroidManifest.xml'));
    if (!manifestFile.existsSync()) {
      valStep
        ..add('AndroidManifest.xml not found', ConsoleColor.red)
        ..finish('Failed', ConsoleColor.red);
      PrintMsg('Build failed', ConsoleColor.brightWhite, '\n•',
          ConsoleColor.brightRed);
      exit(1);
    }
    valStep.finish('Done', ConsoleColor.cyan);

    var ymlLastMod = rushYml.lastModifiedSync();
    var manifestLastMod = manifestFile.lastModifiedSync();

    final loadedYml = loadYaml(rushYml.readAsStringSync());
    var extBox = await Hive.openBox(loadedYml['name']);
    if (!extBox.containsKey('version')) {
      await extBox.putAll({
        'version': 1,
      });
    } else if (!extBox.containsKey('rushYmlMod')) {
      await extBox.putAll({
        'rushYmlMod': ymlLastMod,
      });
    } else if (!extBox.containsKey('manifestMod')) {
      await extBox.putAll({
        'manifestMod': manifestLastMod,
      });
    }

    // TODO:
    // Delete the build dir if there are any changes in the
    // rush.yml or Android Manifest file.

    // if (ymlLastMod.isAfter(extBox.get('rushYmlMod')) ||
    //     manifestLastMod.isAfter(extBox.get('manifestMod'))) {
    //   _cleanBuildDir(dataDir);
    // }

    // Increment version number if this is a production build
    if (_isProd) {
      var version = extBox.get('version') + 1;
      await extBox.put('version', version);
    }

    final dataDir = AppDataMixin.dataStorageDir();

    // Args for spawning the Apache Ant process
    final args = AntArgs(dataDir, _cd, _extType,
        extBox.get('version').toString(), loadedYml['name']);

    final pathToAntEx = p.join(dataDir, 'tools', 'apache-ant', 'bin', 'ant');

    _compile(pathToAntEx, args, Platform.isWindows);
  }

  void _compile(String antPath, AntArgs args, bool runInShell) {
    var count = 0;
    var errCount = 0;
    var warnCount = 0;

    final compStep = BuildStep('Compiling Java sources');
    compStep.init();

    Process.start(antPath, args.toList('javac'), runInShell: runInShell)
        .asStream()
        .asBroadcastStream()
        .listen((process) {
      process.stdout.asBroadcastStream().listen((data) {
        // data is in decimal form, we need to format it.
        final formatted = _format(data);

        // formatted is a list of output messages.
        // Go through each of them, and check if it's the start of error, part
        // of error, or a warning.
        for (final out in formatted) {
          final lines = ErrData.getNoOfLines(out);

          // If lines is the not null then it means that out is infact the first
          // line of the error.
          if (lines != null) {
            count = lines - 1;
            errCount++;
            compStep.add('src' + out.split('src')[1], ConsoleColor.red,
                addSpace: true, prefix: 'ERR', prefClr: ConsoleColor.red);
          } else if (count > 0) {
            // If count is greater than 0, then it means that out is remaining part
            // of the previously identified error.
            count--;
            compStep.add(out, ConsoleColor.red);
          } else if (out.contains('error: ERR ')) {
            errCount++;
            compStep.add(
                out.replaceAll('error: ERR ', '').trim(), ConsoleColor.red,
                addSpace: true, prefix: 'ERR', prefClr: ConsoleColor.red);
          } else {
            if (!out.contains(
                'The following options were not recognized by any processor:')) {
              if (out.contains('warning:')) {
                warnCount++;
                compStep.add(
                    out.replaceAll('warning: ', '').trim(), ConsoleColor.yellow,
                    addSpace: true,
                    prefix: 'WARN',
                    prefClr: ConsoleColor.yellow);
              }
            }
          }
        }
      }, onDone: () {
        if (warnCount > 0) {
          compStep.add('Total warnings: $warnCount', ConsoleColor.yellow,
              addSpace: true);
        }
        if (errCount > 0) {
          compStep
            ..add('Total errors: $errCount', ConsoleColor.red,
                addSpace: warnCount <= 0)
            ..finish('Failed', ConsoleColor.red);
          PrintMsg('Build failed', ConsoleColor.brightWhite, '\n•',
              ConsoleColor.brightRed);
          exit(1);
        } else {
          compStep.finish('Done', ConsoleColor.cyan);

          _process(antPath, args, runInShell);
        }
      });
    });
  }

  void _process(String antPath, AntArgs args, bool runInShell) {
    final procStep = BuildStep('Generating metadata files');
    procStep.init();
    var procErrCount = 0;

    Process.start(antPath, args.toList('process'), runInShell: runInShell)
        .asStream()
        .asBroadcastStream()
        .listen((process) {
      process.stdout.asBroadcastStream().listen((data) {
        final formatted = _format(data);
        for (final out in formatted) {
          if (out.startsWith('ERR')) {
            procStep.add(out.replaceAll('ERR ', ''), ConsoleColor.brightWhite,
                addSpace: true, prefix: 'ERR', prefClr: ConsoleColor.red);
            procErrCount++;
          }
        }
      });
    }, onError: (_) {
      procStep
        ..add('An internal error occured', ConsoleColor.brightBlack)
        ..finish('Failed', ConsoleColor.red);
      PrintMsg('Build failed', ConsoleColor.brightWhite, '\n•',
          ConsoleColor.brightRed);
      exit(2);
    }, onDone: () {
      if (procErrCount > 0) {
        procStep
          ..add('Total errors: $procErrCount', ConsoleColor.red)
          ..finish('Failed', ConsoleColor.red);
        PrintMsg('Build failed', ConsoleColor.brightWhite, '\n•',
            ConsoleColor.brightRed);
        exit(1);
      }
      procStep.finish('Done', ConsoleColor.cyan);

      _dex(antPath, args, runInShell);
    });
  }

  void _dex(String antPath, AntArgs args, bool runInShell) {
    final dexStep = BuildStep('Converting Java bytecode to DEX bytecode');
    dexStep.init();

    Process.start(antPath, args.toList('dex'), runInShell: runInShell)
        .asStream()
        .asBroadcastStream()
        .listen((_) {}, onError: (_) {
      dexStep
        ..add('An internal error occured', ConsoleColor.brightBlack)
        ..finish('Failed', ConsoleColor.red);
      PrintMsg('Build failed', ConsoleColor.brightWhite, '\n•',
          ConsoleColor.brightRed);
      exit(2);
    }, onDone: () {
      dexStep.finish('Done', ConsoleColor.cyan);

      _finalize(antPath, args, runInShell);
    });
  }

  void _finalize(String antPath, AntArgs args, bool runInShell) {
    final asmStep = BuildStep('Finalizing the build');
    asmStep.init();

    Process.start(antPath, args.toList('assemble'), runInShell: runInShell)
        .asStream()
        .asBroadcastStream()
        .listen((_) {}, onError: (_) {
      asmStep
        ..add('An internal error occured', ConsoleColor.brightBlack)
        ..finish('Failed', ConsoleColor.red);
      PrintMsg('Build failed', ConsoleColor.brightWhite, '\n•',
          ConsoleColor.brightRed);
      exit(2);
    }, onDone: () {
      asmStep.finish('Done', ConsoleColor.cyan);
      PrintMsg('Build successful', ConsoleColor.brightWhite, '\n•',
          ConsoleColor.green);
      exit(0);
    });
  }

  /// Converts the given list of decimal char codes into string list and removes
  /// empty lines from it.
  List<String> _format(List<int> charcodes) {
    final stringified = String.fromCharCodes(charcodes);
    final List res = <String>[];
    stringified.split('\r\n').forEach((el) {
      if ('$el'.trim().isNotEmpty) {
        res.add(el.trimRight().replaceAll('[javac] ', ''));
      }
    });
    return res;
  }

  void _cleanBuildDir(String dataDir) {
    var buildDir = Directory(p.join(dataDir, 'workspaces', _extType));
    try {
      buildDir.deleteSync(recursive: true);
    } catch (e) {
      ThrowError(
          message:
              'ERR: Something went wrong while invalidating build caches.');
    }
  }
}
