import 'dart:io' show Directory, File, Platform, exit;

import 'package:hive/hive.dart';
import 'package:path/path.dart' as p;
import 'package:process_runner/process_runner.dart';
import 'package:rush_cli/commands/build_command/helpers/compute.dart';
import 'package:rush_cli/helpers/cmd_utils.dart';
import 'package:rush_cli/helpers/process_streamer.dart';
import 'package:rush_prompt/rush_prompt.dart';

class Compiler {
  final String _cd;
  final String _dataDir;

  Compiler(this._cd, this._dataDir);

  /// Compiles the Java files for this extension project.
  Future<void> compileJava(Box dataBox, BuildStep step) async {
    final instance = DateTime.now();

    final org = await dataBox.get('org') as String;
    final version = await dataBox.get('version') as int;
    final name = await dataBox.get('name') as String;

    final args = await _getJavacArgs(name, org, version);

    final result =
        await _startProcess(_StartProcessArgs(cd: _cd, cmdArgs: args));

    if (result.result == Result.error) {
      throw Exception();
    }

    await _generateInfoFilesIfNoBlocks(org, version, instance, step);
  }

  /// Compiles the Kotlin files for this extension project.
  Future<void> compileKt(Box dataBox, BuildStep step) async {
    final instance = DateTime.now();
    final org = await dataBox.get('org') as String;

    final ktcArgs = _getKtcArgs(org);
    final kaptArgs = await _getKaptArgs(dataBox);

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

    final store = ErrWarnStore();
    for (final result in results) {
      store.incErrors(result.store.getErrors);
      store.incWarnings(result.store.getWarnings);
    }

    if (results.any((el) => el.result == Result.error)) {
      throw Exception();
    }

    await _generateInfoFilesIfNoBlocks(
        org, await dataBox.get('version') as int, instance, step);
  }

  /// Generates info files if no block annotations are declared.
  Future<void> _generateInfoFilesIfNoBlocks(
      String org, int version, DateTime instance, BuildStep step) async {
    final filesDir = p.join(_dataDir, 'workspaces', org, 'files');
    final componentsJson = File(p.join(filesDir, 'components.json'));

    final classpath = CmdUtils.generateClasspath([
      Directory(p.join(_dataDir, 'tools', 'processor')),
      Directory(p.join(_dataDir, 'tools', 'kotlinc', 'lib'))
    ]);

    if (!componentsJson.existsSync() ||
        componentsJson.lastModifiedSync().isBefore(instance)) {
      final args = <String>[
        'java',
        '-cp',
        classpath,
        'io.shreyash.rush.InfoFilesGeneratorKt',
        _cd,
        version.toString(),
        org,
        filesDir,
      ];

      final result =
          await _startProcess(_StartProcessArgs(cd: _cd, cmdArgs: args));

      if (result.result == Result.error) {
        throw Exception();
      }

      step.log(LogType.warn, 'No declaration of any block annotation found');
    }
  }

  /// Returns the command line args required for compiling Java
  /// sources.
  Future<List<String>> _getJavacArgs(
      String name, String org, int version) async {
    final classesDir = Directory(p.join(_dataDir, 'workspaces', org, 'classes'))
      ..createSync(recursive: true);

    final classpath = CmdUtils.generateClasspath([
      Directory(p.join(_dataDir, 'dev-deps')),
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
      ..addAll(['-d', classesDir.path])
      ..addAll(['-cp', classpath])
      ..addAll([...apArgs])
      ..addAll([...CmdUtils.getJavaSourceFiles(srcDir)]);

    final javacRsh = File(p.join(filesDir.path, 'javac.rsh'))
      ..createSync()
      ..writeAsStringSync(args.join('\n'));

    return ['javac', '@${javacRsh.path}'];
  }

  /// Returns command line args required for compiling Kotlin sources.
  List<String> _getKtcArgs(String org) {
    final kotlinc = p.join(_dataDir, 'tools', 'kotlinc', 'bin',
        'kotlinc' + (Platform.isWindows ? '.bat' : ''));

    final classpath = CmdUtils.generateClasspath([
      Directory(p.join(_dataDir, 'dev-deps')),
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

    return [kotlinc, '@${argFile.path}'];
  }

  /// Returns command line args required for running the Kapt
  /// compiler plugin. Kapt is required for processing annotations
  /// in Kotlin sources and needs to be invoked separately.
  Future<List<String>> _getKaptArgs(Box box) async {
    final apDir = Directory(p.join(_dataDir, 'tools', 'processor'));

    final classpath = CmdUtils.generateClasspath([
      Directory(p.join(_dataDir, 'dev-deps')),
      Directory(p.join(_cd, 'deps')),
      apDir,
    ], exclude: [
      'processor.jar'
    ]);

    final toolsJar = p.join(_dataDir, 'tools', 'other', 'tools.jar');

    final org = await box.get('org') as String;

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

    final kotlinc = p.join(
        kotlincDir, 'bin', 'kotlinc' + (Platform.isWindows ? '.bat' : ''));

    final argFile = _writeArgFile('kapt.rsh', org, args);

    return [kotlinc, '@${argFile.path}'];
  }

  /// Starts a new process with [args.cmdArgs] and prints the output to
  /// the console.
  static Future<ProcessResult> _startProcess(_StartProcessArgs args) async {
    final cd = args.cd;
    final cmdArgs = args.cmdArgs;
    final isParallelProcess = args.isParallelProcess;

    final result = await ProcessStreamer.stream(cmdArgs, cd,
        trackAlreadyPrinted: isParallelProcess, printNormalOutputAlso: true);

    return result;
  }

  /// Returns base64 encoded options required by the Rush annotation processor.
  /// This is only needed when running Kapt, as it doesn't support passing
  /// options to the annotation processor in textual form.
  Future<String> _getEncodedApOpts(Box box) async {
    final name = await box.get('name') as String;
    final org = await box.get('org') as String;
    final version = await box.get('version') as int;

    final filesDir = Directory(p.join(_dataDir, 'workspaces', org, 'files'))
      ..createSync(recursive: true);

    final opts = [
      'root=${_cd.replaceAll('\\', '/')}',
      'extName=$name',
      'org=$org',
      'version=$version',
      'output=${filesDir.path}'
    ].join(';');

    final boxOpts = (await box.get('apOpts') ?? {'': ''}) as Map;

    if (opts == boxOpts['raw']) {
      return boxOpts['encoded'] as String;
    }

    final classpath = CmdUtils.generateClasspath([
      File(p.join(_dataDir, 'tools', 'processor', 'processor.jar')),
      File(p.join(_dataDir, 'dev-deps', 'kotlin-stdlib.jar'))
    ]);

    // The encoding is done by the processor. This is because I was unable to
    // implement the function for encoding the options in Dart. This class is
    // a part of processor module in rush annotation processor repo.
    final res = await ProcessRunner().runProcess(
        ['java', '-cp', classpath, 'io.shreyash.rush.OptsEncoderKt', opts]);

    if (res.exitCode == 0) {
      await box.put('apOpts',
          <String, String>{'raw': opts, 'encoded': res.stdout.trim()});

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
