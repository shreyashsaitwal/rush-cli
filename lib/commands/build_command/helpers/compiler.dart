import 'dart:io' show Directory, File, Platform, exit;

import 'package:hive/hive.dart';
import 'package:path/path.dart' as p;
import 'package:process_run/shell.dart';
import 'package:process_runner/process_runner.dart';
import 'package:rush_cli/helpers/cmd_utils.dart';
import 'package:rush_cli/helpers/process_streamer.dart';
import 'package:rush_prompt/rush_prompt.dart';

class Compiler {
  final String _cd;
  final String _dataDir;

  Compiler(this._cd, this._dataDir);

  /// Compiles the Java files for this extension project.
  Future<void> compileJava(Box dataBox, BuildStep step) async {
    final args = await _getJavacArgs(await dataBox.get('name'),
        await dataBox.get('org'), await dataBox.get('version'));

    final stream = ProcessStreamer.stream(args);

    try {
      await _printResultToConsole(stream, step);
    } catch (e) {
      rethrow;
    }
  }

  /// Returns the command line args required for compiling Java
  /// sources.
  Future<List<String>> _getJavacArgs(
      String name, String org, int version) async {
    final classesDir = Directory(p.join(_dataDir, 'workspaces', org, 'classes'))
      ..createSync(recursive: true);

    final classpath = CmdUtils.generateClasspath([
      Directory(p.join(_cd, '.rush', 'dev-deps')),
      Directory(p.join(_cd, 'deps')),
      Directory(p.join(_dataDir, 'tools', 'processor')),
    ], classesDir: classesDir);

    final filesDir = Directory(p.join(_dataDir, 'workspaces', org, 'files'))
      ..createSync(recursive: true);

    // Args for annotation processor
    final apArgs = <String>[
      '-Xlint:-options',
      '-Aroot=$_cd',
      '-AextName=$name',
      '-Aorg=$org',
      '-Aversion=$version',
      '-Aoutput=${filesDir.path}',
    ];

    final srcDir = Directory(p.join(_cd, 'src'));
    final args = <String>[];

    args
      ..add('javac')
      ..addAll(['-d', classesDir.path])
      ..addAll(['-cp', classpath])
      ..addAll([...apArgs])
      ..addAll([...CmdUtils.getJavaSourceFiles(srcDir)]);

    return args;
  }

  /// Compiles the Kotlin files for this extension project.
  Future<void> compileKt(Box dataBox, BuildStep step) async {
    final ktcArgs = _getKtcArgs(await dataBox.get('org'));
    final kaptArgs = await _getKaptArgs(dataBox);

    final streamKtc = ProcessStreamer.stream(ktcArgs);
    final streamKapt = ProcessStreamer.stream(kaptArgs);

    try {
      await Future.wait([
        _printResultToConsole(streamKtc, step, forKt: true),
        _printResultToConsole(streamKapt, step, forKt: true),
      ]);
    } catch (e) {
      rethrow;
    }
  }

  /// Returns commmand line args required for compiling Kotlin sources.
  List<String> _getKtcArgs(String org) {
    final kotlincJvm = p.join(_dataDir, 'tools', 'kotlinc', 'bin',
        'kotlinc-jvm' + (Platform.isWindows ? '.bat' : ''));

    final classpath = CmdUtils.generateClasspath([
      Directory(p.join(_cd, '.rush', 'dev-deps')),
      Directory(p.join(_cd, 'deps')),
    ]);

    final classesDir = Directory(p.join(_dataDir, 'workspaces', org, 'classes'))
      ..createSync(recursive: true);
    final srcDir = p.join(_cd, 'src');

    final args = <String>[];
    args
      ..addAll(['-d', classesDir.path])
      ..addAll(['-cp', '"$classpath"'])
      ..add(srcDir);

    final argFile = _writeArgFile('compile.rsh', org, args);

    return [kotlincJvm, '@${argFile.path}'];
  }

  /// Returns command line args required for running the Kapt
  /// compiler plugin. Kapt is required for processing annotations
  /// in Kotlin sources and needs to be invoked separately.
  Future<List<String>> _getKaptArgs(Box box) async {
    final apDir = Directory(p.join(_dataDir, 'tools', 'processor'));

    final classpath = CmdUtils.generateClasspath([
      Directory(p.join(_cd, '.rush', 'dev-deps')),
      Directory(p.join(_cd, 'deps')),
      apDir,
    ], exclude: [
      'processor.jar'
    ]);

    final whichJavac = whichSync('javac') ?? whichSync('jar');
    final toolsJar =
        p.join(p.dirname(p.dirname(whichJavac!)), 'lib', 'tools.jar');

    final org = await box.get('org');

    final prefix = '-P "plugin:org.jetbrains.kotlin.kapt3:';
    final kaptDir = Directory(p.join(_dataDir, 'workspaces', org, 'kapt'))
      ..createSync(recursive: true);

    final kotlincDir = p.join(_dataDir, 'tools', 'kotlinc');
    final args = <String>[];

    args
      ..addAll(['-cp', '"$classpath"'])
      ..add('-Xplugin="$toolsJar"')
      ..add(
          '-Xplugin="${p.join(kotlincDir, 'lib', 'kotlin-annotation-processing.jar')}"')
      ..add(prefix + 'sources=' + kaptDir.path + '"')
      ..add(prefix + 'classes=' + kaptDir.path + '"')
      ..add(prefix + 'stubs=' + kaptDir.path + '"')
      ..add(prefix + 'aptMode=stubsAndApt' + '"')
      ..add(prefix + 'apclasspath=' + p.join(apDir.path, 'processor.jar') + '"')
      ..add(prefix + 'apoptions=' + await _getEncodedApOpts(box) + '"')
      ..add(p.join(_cd, 'src')); // src dir

    final kotlincJvm = p.join(
        kotlincDir, 'bin', 'kotlinc-jvm' + (Platform.isWindows ? '.bat' : ''));

    final argFile = _writeArgFile('kapt.rsh', org, args);

    return [kotlincJvm, '@${argFile.path}'];
  }

  /// This list keeps a track of the errors/warnings/etc. that have
  /// been printed already while Kotlin compilation.
  final alreadyPrinted = <String>[];

  /// Starts listening to the events emitted by [stream] and prints them
  /// to the console in a colorful way. For example, errors get printed
  /// in red whereas warnings in yellow.
  Future<void> _printResultToConsole(
      Stream<ProcessRunnerResult> stream, BuildStep step,
      {bool forKt = false}) async {
    final warnPattern = RegExp(r'(\s*warning:\s?)+');
    final errPattern = RegExp(r'(\s*error:\s?)+');

    // These patterns are either useless or don't make sense in Rush's
    // context. For example, the error and warning count printed by
    // javac is not necessary to print as Rush itself keeps track of
    // them.
    final excludePatterns = [
      RegExp('The following options were not recognized'),
      RegExp(r'\d+\s*warnings?\s?'),
      RegExp(r'\d+\s*errors?\s?'),
    ];

    try {
      await for (final result in stream) {
        final stdout = result.output.split('\n');

        var skip = false;

        stdout
            .where((line) =>
                line.trim().isNotEmpty &&
                !excludePatterns.any((el) => el.hasMatch(line)))
            .forEach((line) {
          if (line.startsWith(_cd)) {
            line = line.replaceFirst(p.join(_cd, 'src'), 'src');
          }

          // When compiling Kotlin, the Kotlin compiler and the annotation
          // processing plugin, kapt, are run in parallel to reduce the
          // overall compilation time. Because of this if there are errors,
          // they will be printed twice.

          // Therefore, to prevent this from happening, we keep a track of
          // all sorts of things that are already printed while compiling
          // Kotlin in the [alreadyPrinted] list, and everytime there's
          // something new to print we check if that was already printed or
          // not.

          if (forKt && alreadyPrinted.contains(line)) {
            skip = true;
          } else if (line.contains(warnPattern)) {
            line = line.replaceFirst(
                warnPattern, line.startsWith(warnPattern) ? '' : ' ');

            skip = false;
            step.logWarn(line, addSpace: true);
          } else if (!skip) {
            step.logWarn(' ' * 5 + line, addPrefix: false);
          }
        });
      }
    } on ProcessRunnerException catch (e) {
      final stderr = e.result?.stderr.split('\n') ?? [];

      var gotErr = true;
      var skip = false;

      stderr
          .where((line) =>
              line.trim().isNotEmpty &&
              !excludePatterns.any((el) => el.hasMatch(line)))
          .forEach((line) {
        if (line.startsWith(_cd)) {
          line = line.replaceFirst(p.join(_cd, 'src'), 'src');
        }

        if (forKt && alreadyPrinted.contains(line)) {
          skip = true;
        } else if (line.contains(errPattern)) {
          final msg = line.replaceFirst(
              errPattern, line.startsWith(errPattern) ? '' : ' ');

          gotErr = true;
          skip = false;

          alreadyPrinted.add(line);
          step.logErr(msg, addSpace: true);
        } else if (line.contains(warnPattern)) {
          final msg = line.replaceFirst(
              warnPattern, line.startsWith(warnPattern) ? '' : ' ');

          gotErr = false;
          skip = false;

          alreadyPrinted.add(line);
          step.logWarn(msg, addSpace: true);
        } else if (!skip) {
          if (gotErr) {
            step.logErr(' ' * 4 + line, addPrefix: false);
          } else {
            step.logWarn(' ' * 5 + line, addPrefix: false);
          }
        }
      });

      rethrow;
    } catch (e) {
      step.logErr(e.toString().trim());
      rethrow;
    }
  }

  /// Returns base64 encoded options required by the Rush annotation processor.
  /// This is only needed when running Kapt, as it doesn't support passing
  /// options to the annotation processor in textual form.
  Future<String> _getEncodedApOpts(Box box) async {
    final name = await box.get('name');
    final org = await box.get('org');
    final version = await box.get('version');

    final filesDir = Directory(p.join(_dataDir, 'workspaces', org, 'files'))
      ..createSync(recursive: true);

    final opts = [
      'root=${_cd.replaceAll('\\', '/')}',
      'extName=$name',
      'org=$org',
      'version=$version',
      'output=${filesDir.path}'
    ].join(';');

    final boxOpts = (await box.get('apOpts') ?? {}) as Map;

    if (opts == boxOpts['raw']) {
      return boxOpts['encoded'];
    }

    final processorJar =
        p.join(_dataDir, 'tools', 'processor', 'processor.jar');

    // The encoding is done by Java. This is because I was unable to implement
    // the function for encoding the options in Dart. This class is a part of
    // processor module in rush annotation processor repo.
    final res = await ProcessRunner().runProcess(
        ['java', '-cp', processorJar, 'io.shreyash.rush.OptsEncoder', opts]);

    if (res.stderr.isEmpty) {
      await box.put('apOpts',
          <String, String>{'raw': opts, 'encoded': res.stdout.trim()});

      return res.stdout.trim();
    } else {
      Logger.logErr('Something went wrong...', addSpace: true);
      Logger.logErr(res.stderr, addPrefix: false);
      exit(1);
    }
  }

  /// Writes an argfile which holds the arguments required for running kotlinc
  /// and Kapt.
  ///
  /// This is done because kotlinc showed different behavior on different shells
  /// on Windows. Directly passing args to the process runner never worked, but
  /// if the same args were executed from CMD, it would work. Although won't
  /// work on Git Bash and PowerShell.
  File _writeArgFile(String fileName, String org, List<String> args) {
    final file = File(p.join(_dataDir, 'workspaces', org, 'files', fileName))
      ..createSync(recursive: true);

    var contents = '';

    args.forEach((line) {
      contents += line.replaceAll('\\', '/') + '\n';
    });

    file.writeAsStringSync(contents);

    return file;
  }
}
