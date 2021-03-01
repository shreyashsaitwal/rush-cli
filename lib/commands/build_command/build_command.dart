import 'dart:io';

import 'package:args/command_runner.dart';
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
              'Generates two flavors of extensions, one that uses AndroidX libraries, and other that uses support libraries. The later is supposed to be used with builders that haven\'t yet migrated to AndroidX.');
  }

  final runInShell = Platform.isWindows;

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
      ..writeLine(
          '     Marks this build as a release build, which results in the version number being incremented by one.')
      ..resetColorAttributes()
      ..writeLine();
  }

  /// Builds the extension in the current directory
  @override
  Future<void> run() async {
    PrintArt();
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
    } else {
      valStep.add('Metadata file (rush.yml)', ConsoleColor.brightWhite,
          addSpace: true,
          prefix: 'OKAY',
          prefBgClr: ConsoleColor.brightGreen,
          prefClr: ConsoleColor.black);
    }

    final manifestFile = File(p.join(_cd, 'src', 'AndroidManifest.xml'));
    if (!manifestFile.existsSync()) {
      valStep
        ..add('AndroidManifest.xml not found', ConsoleColor.red)
        ..finish('Failed', ConsoleColor.red);
      PrintMsg('Build failed', ConsoleColor.brightWhite, '\n•',
          ConsoleColor.brightRed);
      exit(1);
    } else {
      valStep.add('AndroidManifest.xml file', ConsoleColor.brightWhite,
          addSpace: true,
          prefix: 'OKAY',
          prefBgClr: ConsoleColor.brightGreen,
          prefClr: ConsoleColor.black);
    }
    valStep.finish('Done', ConsoleColor.cyan);

    final dataDir = AppDataMixin.dataStorageDir();

    Hive.init(p.join(_cd, '.rush'));
    final extBox = await Hive.openBox('data');

    // Load rush.yml in a Dart understandable way.
    final loadedYml = loadYaml(rushYml.readAsStringSync());

    // This is done in case the user deletes the .rush directory.
    if (!extBox.containsKey('version')) {
      await extBox.put('version', 1);
    } else if (!extBox.containsKey('rushYmlLastMod')) {
      await extBox.put('rushYmlLastMod', rushYml.lastModifiedSync());
    } else if (!extBox.containsKey('srcDirLastMod')) {
      await extBox.put('srcDirLastMod', rushYml.lastModifiedSync());
    } else if (!extBox.containsKey('org') ||
        extBox.get('org') != _getPackage(loadedYml)) {
      await extBox.put('org', _getPackage(loadedYml));
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
      _cleanDir(p.join(dataDir, 'workspaces', extBox.get('org')));
    }

    // Increment version number if this is a production build.
    final isProd = argResults['release'];
    if (isProd) {
      var version = extBox.get('version') + 1;
      await extBox.put('version', version);
      _cleanDir(p.join(dataDir, 'workspaces', extBox.get('org')));
      areFilesModified = true;
    }

    // Args for spawning the Apache Ant process
    final args = AntArgs(dataDir, _cd, extBox.get('org'),
        extBox.get('version').toString(), loadedYml['name'], argResults['support-lib']);

    final scriptPath = Platform.script.toFilePath(windows: Platform.isWindows);

    final pathToAntEx = p.join(scriptPath.split('bin').first, 'tools',
        'apache-ant-1.10.9', 'bin', 'ant');

    // This box stores the warnings/errors that appeared while building
    // the extension. This is done in order to skip the compilation in
    // case there is no change in src dir and/or rush.yml; just print
    // the previous errors/warnings stored in the box.
    final buildBox = await Hive.openBox('build');

    if (!buildBox.containsKey('count')) {
      await buildBox.put('count', 1);
    } else {
      final i = (await buildBox.get('count') as int) + 1;
      await buildBox.put('count', i);
    }

    await _compile(pathToAntEx, args,
        areFilesModified || await buildBox.get('count') == 1, buildBox);
  }

  /// Compiles all the Java files located at _cd/src.
  Future<void> _compile(
      String antPath, AntArgs args, bool shouldRecompile, Box box) async {
    var errCount = 0;
    var warnCount = 0;

    final compStep = BuildStep('Compiling Java files');
    compStep.init();

    // Compile only if there are any changes in the src dir and/or rush.yml.
    if (shouldRecompile) {
      var count = 0;

      // Delete previous errors and warnings
      if (box.containsKey('totalErr')) {
        await box.delete('totalErr');
      }
      if (box.containsKey('totalWarn')) {
        await box.delete('totalWarn');
      }

      Process.start(antPath, args.toList('javac'), runInShell: runInShell)
          .asStream()
          .asBroadcastStream()
          .listen((process) {
        final temp = <String>[];
        process.stdout.asBroadcastStream().listen((data) async {
          // format data in human readable format
          final formatted = _format(data);

          // formatted is a list of output messages.
          // Go through each of them, and check if it's the start of error, part
          // of error, or a warning.
          for (final out in formatted) {
            // print(out);
            final lines = ErrData.getNoOfLines(out);

            // If lines is the not null then it means that out is in fact the first
            // line of the error.
            if (lines != null) {
              count = lines - 1;
              errCount++;

              final msg = 'src' + out.split('src').last;
              temp.add(msg);
              compStep.add(msg, ConsoleColor.red,
                  addSpace: true,
                  prefix: 'ERR',
                  prefBgClr: ConsoleColor.brightRed,
                  prefClr: ConsoleColor.brightWhite);
            } else if (count > 0) {
              // If count is greater than 0, then it means that out is remaining part
              // of the previously identified error.

              count--;
              temp.add(out);
              compStep.add(out, ConsoleColor.red);
              if (count == 0) {
                await box.put('err$errCount', temp);
                temp.clear();
              }
            } else if (out.contains('ERR ')) {
              // If out contains 'ERR' then it means that this error is from
              // the annotaion processor. All errors coming from annotation processor
              // are one liner, so, no need for any over head, we can directly print them.

              errCount++;
              final msg = out.split('ERR ').last;
              compStep.add(msg, ConsoleColor.red,
                  addSpace: true,
                  prefix: 'ERR',
                  prefBgClr: ConsoleColor.red,
                  prefClr: ConsoleColor.brightWhite);

              // No need to add this err in temp. Since it's one liner, it can directly
              // be added to the box.
              await box.put('err$errCount', msg);
            } else if (out.contains('error: ')) {
              // If this condition is reached then it means this of error *maybe*
              // doesn't fall in any of the javac err categories.
              // So, we increase the count by 2 assuming this error is a 3-liner
              // since most javac errors are 3-liner.

              count += 2;
              errCount++;
              final msg = 'src' + out.split('src').last;

              temp.add(msg);
              compStep.add(msg, ConsoleColor.red,
                  addSpace: true, prefix: 'ERR', prefBgClr: ConsoleColor.red);
            } else if (out.contains('warning:') &&
                !out.contains(
                    'The following options were not recognized by any processor:')) {
              warnCount++;

              final msg = out.replaceAll('warning: ', '').trim();
              compStep.add(msg, ConsoleColor.yellow,
                  addSpace: true,
                  prefix: 'WARN',
                  prefBgClr: ConsoleColor.yellow,
                  prefClr: ConsoleColor.black);

              // Warnings are usually one liner, so, we can add them to the box directly.
              await box.put('warn$warnCount', msg);
            }
          }
        }, onDone: () async {
          await box.put('totalErr', errCount);
          await box.put('totalWarn', warnCount);

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
          }
          compStep.finish('Done', ConsoleColor.cyan);
          _process(antPath, args);
        }, onError: (_) {
          compStep
            ..add('Total errors: $errCount', ConsoleColor.red,
                addSpace: warnCount <= 0)
            ..finish('Failed', ConsoleColor.red);
          PrintMsg('Build failed', ConsoleColor.brightWhite, '\n•',
              ConsoleColor.brightRed);
          exit(1);
        });
      });
    } else {
      final totalWarn = box.get('totalWarn') ?? 0;
      final totalErr = box.get('totalErr') ?? 0;

      if (totalWarn > 0) {
        for (var i = 0; i < totalWarn; i++) {
          final warn = box.get('warn${i + 1}');
          compStep.add(warn, ConsoleColor.yellow,
              addSpace: true,
              prefix: 'WARN',
              prefBgClr: ConsoleColor.yellow,
              prefClr: ConsoleColor.black);
        }
        compStep.add('Total warnings: $warnCount', ConsoleColor.yellow,
            addSpace: true);
      }

      if (totalErr > 0) {
        for (var i = 0; i < totalErr; i++) {
          final err = box.get('err${i + 1}');
          err.forEach((el) {
            if (err.indexOf(el) == 0) {
              compStep.add(el, ConsoleColor.red,
                  addSpace: true,
                  prefix: 'ERR',
                  prefClr: ConsoleColor.brightWhite,
                  prefBgClr: ConsoleColor.brightRed);
            } else {
              compStep.add(el, ConsoleColor.red);
            }
          });
        }
        compStep
          ..add('Total errors: $totalErr', ConsoleColor.red,
              addSpace: totalWarn <= 0)
          ..finish('Failed', ConsoleColor.red);
        PrintMsg('Build failed', ConsoleColor.brightWhite, '\n•',
            ConsoleColor.brightRed);
        exit(1);
      }

      compStep.finish('Done', ConsoleColor.cyan);
      _process(antPath, args);
    }
  }

  /// Further process the extension by generating extension files, adding
  /// libraries and jaring the extension.
  void _process(String antPath, AntArgs args) {
    final procStep = BuildStep('Generating extension files');
    procStep.init();
    var procErrCount = 0;

    Process.start(antPath, args.toList('process'), runInShell: runInShell)
        .asStream()
        .asBroadcastStream()
        .listen((process) {
      process.stdout.asBroadcastStream().listen((data) {
        final formatted = _format(data);
        for (final out in formatted) {
          // print(out);
          if (out.startsWith('ERR')) {
            procStep.add(out.replaceAll('ERR ', ''), ConsoleColor.brightWhite,
                addSpace: true, prefix: 'ERR', prefBgClr: ConsoleColor.red);
            procErrCount++;
          }
        }
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

        _dex(antPath, args);
      });
    });
  }

  /// Convert generated extension JAR file from previous step into DEX
  /// bytecode.
  void _dex(String antPath, AntArgs args) {
    final dexStep = BuildStep('Converting Java bytecode to DEX bytecode');
    dexStep.init();

    Process.start(antPath, args.toList('dex'), runInShell: runInShell)
        .asStream()
        .asBroadcastStream()
        .listen((process) {
      process.stdout.asBroadcastStream().listen((data) {
        // TODO Listen to errors
      }, onError: (_) {
        dexStep
          ..add('An internal error occured', ConsoleColor.brightBlack)
          ..finish('Failed', ConsoleColor.red);
        PrintMsg('Build failed', ConsoleColor.brightWhite, '\n•',
            ConsoleColor.brightRed);
        exit(2);
      }, onDone: () {
        dexStep.finish('Done', ConsoleColor.cyan);

        _finalize(antPath, args);
      });
    });
  }

  /// Finalize the build.
  void _finalize(String antPath, AntArgs args) {
    final asmStep = BuildStep('Finalizing the build');
    asmStep.init();

    Process.start(antPath, args.toList('assemble'), runInShell: runInShell)
        .asStream()
        .asBroadcastStream()
        .listen((process) {
      process.stdout.asBroadcastStream().listen((data) {
        // TODO Listen to errors
      }, onError: (_) {
        asmStep
          ..add('An internal error occured', ConsoleColor.brightBlack)
          ..finish('Failed', ConsoleColor.red);
        PrintMsg('Build failed', ConsoleColor.brightWhite, '\n•',
            ConsoleColor.brightRed);
        exit(2);
      }, onDone: () {
        asmStep.finish('Done', ConsoleColor.cyan);
        PrintMsg('Build successful', ConsoleColor.brightWhite, '\n•',
            ConsoleColor.brightGreen);
        exit(0);
      });
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

  /// Deletes directory located at [path] recursively.
  void _cleanDir(String path) {
    final dir = Directory(path);
    if (dir.existsSync()) {
      try {
        dir.deleteSync(recursive: true);
      } catch (e) {
        ThrowError(
            message:
                'ERR Something went wrong while invalidating build caches.');
      }
    }
  }

  String _getPackage(YamlMap loadedYml) {
    final srcDir = Directory(p.join(_cd, 'src'));
    var path = '';

    for (final file in srcDir.listSync(recursive: true)) {
      if (file is File &&
          p.basename(file.path) == '${loadedYml['name']}.java') {
        path = file.path;
        break;
      }
    }

    final struct = p.split(path.split(p.join(_cd, 'src')).last);
    struct.removeAt(0);

    var package = '';
    var isFirst = true;
    for (final dirName in struct) {
      if (!dirName.endsWith('.java')) {
        if (isFirst) {
          package += dirName;
          isFirst = false;
        } else {
          package += '.' + dirName;
        }
      }
    }

    return package;
  }
}
