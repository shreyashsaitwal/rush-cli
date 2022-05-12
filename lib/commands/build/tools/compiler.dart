import 'dart:io' show Directory, File, Platform, exit;

import 'package:hive/hive.dart';
import 'package:path/path.dart' as p;
import 'package:process_runner/process_runner.dart';
import 'package:rush_cli/commands/build/hive_adapters/remote_dep_index.dart';
import 'package:rush_cli/commands/build/utils/build_utils.dart';
import 'package:rush_cli/commands/build/utils/compute.dart';
import 'package:rush_cli/commands/build/hive_adapters/build_box.dart';
import 'package:rush_cli/models/rush_yaml/rush_yaml.dart';
import 'package:rush_cli/utils/cmd_utils.dart';
import 'package:rush_cli/utils/process_streamer.dart';
import 'package:rush_cli/services/file_service.dart';
import 'package:rush_prompt/rush_prompt.dart';

class _StartProcessArgs {
  final String projectRoot;
  final List<String> cmdArgs;
  final bool isParallelProcess;

  _StartProcessArgs({
    required this.projectRoot,
    required this.cmdArgs,
    this.isParallelProcess = false,
  });
}

class Compiler {
  final FileService _fs;
  final RushYaml _rushYaml;
  final Box<BuildBox> _buildBox;

  Compiler(this._fs, this._rushYaml, this._buildBox);

  /// Compiles the Java files for this extension project.
  Future<void> compileJava(BuildStep step, Set<RemoteDepIndex> depIndex) async {
    final args = await _getJavacArgs(depIndex);
    final result = await _startProcess(
        _StartProcessArgs(projectRoot: _fs.cwd, cmdArgs: args));
    if (!result.success) {
      throw Exception();
    }
  }

  /// Compiles the Kotlin files for this extension project.
  Future<void> compileKt(BuildStep step, Set<RemoteDepIndex> depIndex) async {
    final ktcArgs = _getKtcArgs(depIndex);
    final kaptArgs = await _getKaptArgs(depIndex);

    // [ProcessStreamer] uses the build box to track the messages that were
    // logged previously during this build. This is done only when at least two
    // processes are running simultaneously so that we don't log the same messages
    // more than once.
    // But here, we are spawing a new isolate by using the [compute] method, and
    // therefore, to keep the OS happy by freeing the `build.lock` file so that
    // other Hive instances from different isolates can access it, we need to
    // close this instance of build box.
    await _buildBox.close();
    final results = await Future.wait([
      compute(
          _startProcess,
          _StartProcessArgs(
              projectRoot: _fs.cwd, cmdArgs: ktcArgs, isParallelProcess: true)),
      compute(
          _startProcess,
          _StartProcessArgs(
              projectRoot: _fs.cwd,
              cmdArgs: kaptArgs,
              isParallelProcess: true)),
    ]);

    // Clean the previously logged messages from build box so that they don't
    // affect next build.
    await BuildUtils.deletePreviouslyLoggedFromBuildBox();

    final store = ErrWarnStore();
    for (final result in results) {
      store.incErrors(result.store.getErrors);
      store.incWarnings(result.store.getWarnings);
    }

    if (results.any((el) => !el.success)) {
      throw Exception();
    }
  }

  /// Returns the command line args required for compiling sources.
  Future<List<String>> _getJavacArgs(Set<RemoteDepIndex> depIndex) async {
    final filesDir = Directory(p.join(_fs.buildDir, 'files'))
      ..createSync(recursive: true);

    // Args for annotation processor
    final apArgs = <String>[
      '-Xlint:-options',
      '-AprojectRoot=${_fs.cwd}',
      '-AoutputDir=${filesDir.path}',
    ];

    final classesDir = Directory(p.join(_fs.buildDir, 'classes'))
      ..createSync(recursive: true);

    final classpath =
        BuildUtils.classpathStringForDeps(_fs, _rushYaml, depIndex) +
            CmdUtils.cpSeparator +
            CmdUtils.classpathString(
                [Directory(p.join(_fs.toolsDir, 'processor')), classesDir]);
    final srcDir = Directory(_fs.srcDir);
    final args = <String>[];

    args
      ..addAll(['-encoding', 'UTF8'])
      ..addAll(['-d', classesDir.path])
      ..addAll(['-cp', classpath])
      ..addAll([...apArgs])
      ..addAll([...CmdUtils.getJavaSourceFiles(srcDir)]);

    // Here, we're creating an arg file instead of directy passing the args to
    // the process because the [Process] can't handle too many source files (>100)
    // and fails to execute javac.
    final javacRsh = File(p.join(filesDir.path, 'javac.rsh'))
      ..createSync()
      ..writeAsStringSync(args.join('\n'));

    return ['javac', '@${javacRsh.path}'];
  }

  /// Returns command line args required for compiling Kotlin sources.
  List<String> _getKtcArgs(Set<RemoteDepIndex> depIndex) {
    final kotlinc = p.join(_fs.toolsDir, 'kotlinc', 'bin',
        'kotlinc' + (Platform.isWindows ? '.bat' : ''));

    final classesDir = Directory(p.join(_fs.buildDir, 'classes'))
      ..createSync(recursive: true);

    final classpath =
        BuildUtils.classpathStringForDeps(_fs, _rushYaml, depIndex);

    final args = <String>[];
    args
      ..addAll(['-d', classesDir.path])
      ..addAll(['-cp', '"$classpath"'])
      ..add(_fs.srcDir);

    final argFile = _writeArgFile('compile.rsh', args);
    return [kotlinc, '@${argFile.path}'];
  }

  /// Returns command line args required for running the Kapt compiler plugin.
  /// Kapt is required for processing annotations in Kotlin sources and needs
  /// to be invoked separately.
  Future<List<String>> _getKaptArgs(Set<RemoteDepIndex> depIndex) async {
    final apDir = Directory(p.join(_fs.toolsDir, 'processor'));

    final classpath =
        BuildUtils.classpathStringForDeps(_fs, _rushYaml, depIndex) +
            CmdUtils.cpSeparator +
            CmdUtils.classpathString([
              Directory(p.join(_fs.toolsDir, 'processor')),
            ], exclude: [
              'processor.jar',
            ]);

    final toolsJar = p.join(_fs.toolsDir, 'other', 'tools.jar');

    final pluginPrefix = '-P "plugin:org.jetbrains.kotlin.kapt3:';
    final kaptDir = Directory(p.join(_fs.buildDir, 'kapt'))
      ..createSync(recursive: true);

    final kotlincDir = p.join(_fs.toolsDir, 'kotlinc');
    final args = <String>[
      ...['-cp', '"$classpath"'],
      '-Xplugin="$toolsJar"',
      ...[
        '-Xplugin="${p.join(kotlincDir, 'lib', 'kotlin-annotation-processing.jar')}"',
        pluginPrefix + 'sources=' + kaptDir.path + '"',
        pluginPrefix + 'classes=' + kaptDir.path + '"',
        pluginPrefix + 'stubs=' + kaptDir.path + '"',
        pluginPrefix + 'aptMode=stubsAndApt' + '"',
        pluginPrefix +
            'apclasspath=' +
            p.join(apDir.path, 'processor.jar') +
            '"',
        pluginPrefix + 'apoptions=' + await _getEncodedApOpts() + '"',
      ],
      _fs.srcDir,
    ];

    final kotlinc = p.join(
        kotlincDir, 'bin', 'kotlinc' + (Platform.isWindows ? '.bat' : ''));
    final argFile = _writeArgFile('kapt.rsh', args);
    return [kotlinc, '@${argFile.path}'];
  }

  /// Starts a new process with [args.cmdArgs] and prints the output to the console.
  static Future<ProcessResult> _startProcess(_StartProcessArgs args) async {
    return await ProcessStreamer.stream(
      args.cmdArgs,
      args.projectRoot,
      trackPreviouslyLogged: args.isParallelProcess,
      printNormalOutput: true,
    );
  }

  /// Returns base64 encoded options required by the Rush annotation processor.
  /// This is only needed when running Kapt, as it doesn't support passing
  /// options to the annotation processor in textual form.
  Future<String> _getEncodedApOpts() async {
    final filesDir = Directory(p.join(_fs.buildDir, 'files'))
      ..createSync(recursive: true);

    final opts = [
      'projectRoot=${_fs.cwd.replaceAll('\\', '/')}',
      'outputDir=${filesDir.path}'
    ].join(';');

    final boxOpts = _buildBox.getAt(0)!.kaptOpts;
    if (opts == boxOpts['raw']) {
      return boxOpts['encoded'] as String;
    }

    final classpath = CmdUtils.classpathString([
      File(p.join(_fs.toolsDir, 'processor', 'processor.jar')),
      File(p.join(_fs.devDepsDir, 'kotlin', 'kotlin-stdlib.jar'))
    ]);

    // The encoding is done by the processor. This is because I was unable to
    // implement the function for encoding the options in Dart. This file is
    // a part of processor module in rush annotation processor repo.
    final res = await ProcessRunner().runProcess([
      'java',
      ...['-cp', classpath],
      'io.shreyash.rush.processor.OptsEncoderKt',
      opts,
    ]);

    if (res.exitCode == 0) {
      final updated = _buildBox
          .get(0)!
          .update(kaptOpts: {'raw': opts, 'encoded': res.stdout.trim()});
      await _buildBox.putAt(0, updated);
      return res.stdout.trim();
    } else {
      Logger.log(LogType.erro, 'Something went wrong...');
      Logger.log(LogType.erro, res.stderr, addPrefix: false);
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
  File _writeArgFile(String fileName, List<String> args) {
    final file = File(p.join(_fs.buildDir, 'files', fileName))
      ..createSync(recursive: true);
    var contents = '';

    for (final line in args) {
      contents += line.replaceAll('\\', '/') + '\n';
    }
    file.writeAsStringSync(contents);
    return file;
  }
}
