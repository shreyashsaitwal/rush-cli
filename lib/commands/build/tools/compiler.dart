import 'dart:io' show Directory, File, Platform, exit;

import 'package:hive/hive.dart';
import 'package:path/path.dart' as p;
import 'package:process_runner/process_runner.dart';
import 'package:rush_cli/commands/build/helpers/build_utils.dart';
import 'package:rush_cli/commands/build/helpers/compute.dart';
import 'package:rush_cli/commands/build/hive_adapters/build_box.dart';
import 'package:rush_cli/commands/build/hive_adapters/data_box.dart';
import 'package:rush_cli/commands/build/models/rush_lock/rush_lock.dart';
import 'package:rush_cli/commands/build/models/rush_yaml/rush_yaml.dart';
import 'package:rush_cli/helpers/cmd_utils.dart';
import 'package:rush_cli/helpers/process_streamer.dart';
import 'package:rush_prompt/rush_prompt.dart';

class _StartProcessArgs {
  final String cd;
  final List<String> cmdArgs;
  final bool isParallelProcess;

  _StartProcessArgs({
    required this.cd,
    required this.cmdArgs,
    this.isParallelProcess = false,
  });
}

class Compiler {
  final String _cd;
  final String _dataDir;
  final RushYaml _rushYaml;
  final Box<DataBox> _dataBox;
  final Box<BuildBox> _buildBox;

  Compiler(
      this._cd, this._dataDir, this._rushYaml, this._dataBox, this._buildBox);

  /// Compiles the Java files for this extension project.
  Future<void> compileJava(BuildStep step, RushLock? rushLock) async {
    final instance = DateTime.now();
    final boxVal = _dataBox.getAt(0)!;

    final args = await _getJavacArgs(rushLock);
    final result =
        await _startProcess(_StartProcessArgs(cd: _cd, cmdArgs: args));

    if (result.result == Result.error) {
      throw Exception();
    }

    final componentsJson = File(
        p.join(_dataDir, 'workspaces', boxVal.org, 'files', 'components.json'));
    if (!componentsJson.existsSync() ||
        componentsJson.lastModifiedSync().isBefore(instance)) {
      await _generateInfoFilesIfNoBlocks(step);
    }
  }

  /// Compiles the Kotlin files for this extension project.
  Future<void> compileKt(BuildStep step, RushLock? rushLock) async {
    final instance = DateTime.now();

    final ktcArgs = _getKtcArgs(rushLock);
    final kaptArgs = await _getKaptArgs(rushLock);

    // [ProcessStreamer] uses the build box to track the messages that were
    // logged previously during this build. This is done only when at least two
    // processes are running simultaneously so that we don't log the same messages
    // more than once.
    // But here, we are spawing a new isolate by using the [compute] method, and
    // therefore, to keep the OS happy by freeing the `build.lock` file so that
    // other Hive instances from different isolates can access it, we need to
    // close this instance of build box.
    _buildBox.close();
    final results = await Future.wait([
      compute(
          _startProcess,
          _StartProcessArgs(
              cd: _cd, cmdArgs: ktcArgs, isParallelProcess: true)),
      compute(
          _startProcess,
          _StartProcessArgs(
              cd: _cd, cmdArgs: kaptArgs, isParallelProcess: true)),
    ]);
    BuildUtils.deletePreviouslyLoggedFromBuildBox();

    final store = ErrWarnStore();
    for (final result in results) {
      store.incErrors(result.store.getErrors);
      store.incWarnings(result.store.getWarnings);
    }

    if (results.any((el) => el.result == Result.error)) {
      throw Exception();
    }

    final dataBoxVal = _dataBox.getAt(0)!;
    final componentsJson = File(p.join(
        _dataDir, 'workspaces', dataBoxVal.org, 'files', 'components.json'));
    if (!componentsJson.existsSync() ||
        componentsJson.lastModifiedSync().isBefore(instance)) {
      await _generateInfoFilesIfNoBlocks(step);
    }
  }

  /// Generates info files if no block annotations are declared.
  Future<void> _generateInfoFilesIfNoBlocks(BuildStep step) async {
    final dataBoxVal = _dataBox.get(0)!;

    final filesDir = p.join(_dataDir, 'workspaces', dataBoxVal.org, 'files');
    final classpath = CmdUtils.classpathString([
      Directory(p.join(_dataDir, 'tools', 'processor')),
      Directory(p.join(_dataDir, 'tools', 'kotlinc', 'lib'))
    ]);

    final args = <String>[
      'java',
      ...['-cp', classpath],
      'io.shreyash.rush.processor.InfoFilesGeneratorKt',
      _cd,
      dataBoxVal.version.toString(),
      dataBoxVal.org,
      filesDir,
    ];

    final result =
        await _startProcess(_StartProcessArgs(cd: _cd, cmdArgs: args));
    if (result.result == Result.error) {
      throw Exception();
    }
    step.log(LogType.warn, 'No declaration of any block annotation found');
  }

  /// Returns the command line args required for compiling sources.
  Future<List<String>> _getJavacArgs(RushLock? rushLock) async {
    final dataBoxVal = _dataBox.getAt(0)!;
    final filesDir =
        Directory(p.join(_dataDir, 'workspaces', dataBoxVal.org, 'files'))
          ..createSync(recursive: true);

    // Args for annotation processor
    final apArgs = <String>[
      '-Xlint:-options',
      '-Aroot=$_cd',
      '-AextName=${dataBoxVal.name}',
      '-Aorg=${dataBoxVal.org}',
      '-Aversion=${dataBoxVal.version}',
      '-Aoutput=${filesDir.path}',
    ];

    final classesDir =
        Directory(p.join(_dataDir, 'workspaces', dataBoxVal.org, 'classes'))
          ..createSync(recursive: true);

    final classpath = BuildUtils.classpathStringForDeps(
            _cd, _dataDir, _rushYaml, rushLock) +
        CmdUtils.cpSeparator() +
        CmdUtils.classpathString(
            [Directory(p.join(_dataDir, 'tools', 'processor')), classesDir]);
    final srcDir = Directory(p.join(_cd, 'src'));
    final args = <String>[];

    args
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
  List<String> _getKtcArgs(RushLock? rushLock) {
    final kotlinc = p.join(_dataDir, 'tools', 'kotlinc', 'bin',
        'kotlinc' + (Platform.isWindows ? '.bat' : ''));
    final org = _dataBox.getAt(0)!.org;

    final classesDir = Directory(p.join(_dataDir, 'workspaces', org, 'classes'))
      ..createSync(recursive: true);
    final srcDir = p.join(_cd, 'src');

    final classpath =
        BuildUtils.classpathStringForDeps(_cd, _dataDir, _rushYaml, rushLock);

    final args = <String>[];
    args
      ..addAll(['-d', classesDir.path])
      ..addAll(['-cp', '"$classpath"'])
      ..add(srcDir);

    final argFile = _writeArgFile('compile.rsh', org, args);
    return [kotlinc, '@${argFile.path}'];
  }

  /// Returns command line args required for running the Kapt compiler plugin.
  /// Kapt is required for processing annotations in Kotlin sources and needs
  /// to be invoked separately.
  Future<List<String>> _getKaptArgs(RushLock? rushLock) async {
    final apDir = Directory(p.join(_dataDir, 'tools', 'processor'));

    final classpath =
        BuildUtils.classpathStringForDeps(_cd, _dataDir, _rushYaml, rushLock) +
            CmdUtils.cpSeparator() +
            CmdUtils.classpathString([
              Directory(p.join(_dataDir, 'tools', 'processor')),
            ], exclude: [
              'processor.jar',
            ]);

    final toolsJar = p.join(_dataDir, 'tools', 'other', 'tools.jar');
    final org = _dataBox.getAt(0)!.org;

    final pluginPrefix = '-P "plugin:org.jetbrains.kotlin.kapt3:';
    final kaptDir = Directory(p.join(_dataDir, 'workspaces', org, 'kapt'))
      ..createSync(recursive: true);

    final kotlincDir = p.join(_dataDir, 'tools', 'kotlinc');
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
      p.join(_cd, 'src'),
    ];

    final kotlinc = p.join(
        kotlincDir, 'bin', 'kotlinc' + (Platform.isWindows ? '.bat' : ''));
    final argFile = _writeArgFile('kapt.rsh', org, args);
    return [kotlinc, '@${argFile.path}'];
  }

  /// Starts a new process with [args.cmdArgs] and prints the output to the console.
  static Future<ProcessResult> _startProcess(_StartProcessArgs args) async {
    final cd = args.cd;
    final cmdArgs = args.cmdArgs;
    final isParallelProcess = args.isParallelProcess;

    return await ProcessStreamer.stream(
      cmdArgs,
      cd,
      trackPreviouslyLogged: isParallelProcess,
      printNormalOutput: true,
    );
  }

  /// Returns base64 encoded options required by the Rush annotation processor.
  /// This is only needed when running Kapt, as it doesn't support passing
  /// options to the annotation processor in textual form.
  Future<String> _getEncodedApOpts() async {
    final dataBoxVal = _dataBox.getAt(0)!;
    final filesDir =
        Directory(p.join(_dataDir, 'workspaces', dataBoxVal.org, 'files'))
          ..createSync(recursive: true);

    final opts = [
      'root=${_cd.replaceAll('\\', '/')}',
      'extName=${dataBoxVal.name}',
      'org=${dataBoxVal.org}',
      'version=${dataBoxVal.version}',
      'output=${filesDir.path}'
    ].join(';');

    final boxOpts = _buildBox.getAt(0)!.kaptOpts;
    if (opts == boxOpts['raw']) {
      return boxOpts['encoded'] as String;
    }

    final classpath = CmdUtils.classpathString([
      File(p.join(_dataDir, 'tools', 'processor', 'processor.jar')),
      File(p.join(_dataDir, 'dev-deps', 'kotlin', 'kotlin-stdlib.jar'))
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
      _buildBox.updateKaptOpts({'raw': opts, 'encoded': res.stdout.trim()});
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
  File _writeArgFile(String fileName, String org, List<String> args) {
    final file = File(p.join(_dataDir, 'workspaces', org, 'files', fileName))
      ..createSync(recursive: true);
    var contents = '';

    for (final line in args) {
      contents += line.replaceAll('\\', '/') + '\n';
    }
    file.writeAsStringSync(contents);
    return file;
  }
}
