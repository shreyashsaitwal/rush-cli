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
    final console = Console();
    console
      // ..write(Emojis.checkMark + ' ')
      ..setForegroundColor(ConsoleColor.brightGreen)
      ..write('[0/4] ')
      ..setForegroundColor(ConsoleColor.brightWhite)
      ..writeLine('Validating project files...')
      ..resetColorAttributes();

    File rushYml;
    if (File(p.join(_cd, 'rush.yaml')).existsSync()) {
      rushYml = File(p.join(_cd, 'rush.yaml'));
    } else if (File(p.join(_cd, 'rush.yml')).existsSync()) {
      rushYml = File(p.join(_cd, 'rush.yml'));
    } else {
      console
        ..cursorUp()
        ..eraseLine()
        // ..write(Emojis.crossMark + ' ')
        ..setForegroundColor(ConsoleColor.red)
        ..write('[0/4] ')
        ..writeLine('Unable to find rush.yml in this extension project.')
        ..resetColorAttributes();
      exit(1);
    }

    if (!IsYamlValid.check(rushYml)) {
      console
        ..cursorUp()
        ..eraseLine()
        // ..write(Emojis.crossMark + ' ')
        ..setForegroundColor(ConsoleColor.red)
        ..write('[0/4] ')
        ..writeLine('rush.yml in this extension project is invalid.')
        ..resetColorAttributes();
      exit(1);
    }

    final dataDir = AppDataMixin.dataStorageDir();

    final manifestFile = File(p.join(_cd, 'AndroidManifest.xml'));
    if (!manifestFile.existsSync()) {
      console
        ..cursorUp()
        ..eraseLine()
        // ..write(Emojis.crossMark + ' ')
        ..setForegroundColor(ConsoleColor.red)
        ..write('[0/4] ')
        ..writeLine(
            'Unable to find AndroidManifest.xml in this extension project.')
        ..resetColorAttributes();
      exit(1);
    }

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

    // Args for spawning the Apache Ant process
    final args = AntArgs(dataDir, _cd, _extType,
        extBox.get('version').toString(), loadedYml['name']);

    var count = 0;
    var gotErr = false;

    final pathToAntEx = p.join(dataDir, 'tools', 'apache-ant', 'bin', 'ant');

    console
      // ..write(Emojis.gear)
      ..setForegroundColor(ConsoleColor.brightGreen)
      ..write('[1/4] ')
      ..setForegroundColor(ConsoleColor.brightWhite)
      ..writeLine('Compiling extension...')
      ..resetColorAttributes();
    Process.start(pathToAntEx, args.toList('javac'),
            runInShell: Platform.isWindows)
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
            gotErr = true;
            count = lines - 1;
            console
              ..writeLine()
              ..setBackgroundColor(ConsoleColor.red)
              ..setForegroundColor(ConsoleColor.brightWhite)
              ..write('\tERR')
              ..resetColorAttributes()
              ..setForegroundColor(ConsoleColor.red)
              ..writeErrorLine(' src' + out.split('src')[1]);
          } else if (count > 0) {
            // If count is greater than 0, then it means that out is remaining part
            // of the previously identified error.
            count--;
            console.writeErrorLine('\t' + out);
          } else {
            // TODO: Check for warnings

            // If none of the above conditions are true, out is not an error.
            // console
            //   ..resetColorAttributes()
            //   ..writeLine(out);
          }
        }
      }, onDone: () {
        if (!gotErr) {
          console
            // ..write(Emojis.mantelpieceClock)
            ..setForegroundColor(ConsoleColor.brightGreen)
            ..write('[2/4] ')
            ..setForegroundColor(ConsoleColor.brightWhite)
            ..writeLine('Processing generated files...');
          Process.start(pathToAntEx, args.toList('process'),
                  runInShell: Platform.isWindows)
              .asStream()
              .asBroadcastStream()
              .listen((_) {}, onDone: () {
            console
              // ..write(Emojis.sparkles)
              ..setForegroundColor(ConsoleColor.brightGreen)
              ..write('[3/4] ')
              ..setForegroundColor(ConsoleColor.brightWhite)
              ..writeLine('Compiling Java bytecode to DEX bytecode...');
            Process.start(pathToAntEx, args.toList('dex'),
                    runInShell: Platform.isWindows)
                .asStream()
                .asBroadcastStream()
                .listen((_) {}, onDone: () {
              console
                // ..write(Emojis.unicorn)
                ..setForegroundColor(ConsoleColor.brightGreen)
                ..write('[4/4] ')
                ..setForegroundColor(ConsoleColor.brightWhite)
                ..writeLine('Finalizing the build...');
              Process.start(pathToAntEx, args.toList('assemble'),
                      runInShell: Platform.isWindows)
                  .asStream()
                  .asBroadcastStream()
                  .listen((_) {}, onDone: () {
                exit(0);
              });
            });
          });
        }
      });
    });
    // if (!gotErr) {

    // }
  }

  /// Converts the given list of decimal char codes into string list and removes
  /// empty lines from it.
  List<String> _format(List<int> charcodes) {
    final stringified = String.fromCharCodes(charcodes);
    final List res = <String>[];
    stringified.split('\r\n').forEach((el) {
      if ('$el'.trim().isNotEmpty) {
        res.add(el.trimRight().replaceAll('[javac]', ''));
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
