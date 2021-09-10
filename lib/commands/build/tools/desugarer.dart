import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:rush_cli/commands/build/utils/build_utils.dart';
import 'package:rush_cli/commands/build/utils/compute.dart';
import 'package:rush_cli/models/rush_lock/rush_lock.dart';
import 'package:rush_cli/models/rush_yaml/rush_yaml.dart';
import 'package:rush_cli/utils/cmd_utils.dart';
import 'package:rush_cli/utils/process_streamer.dart';
import 'package:rush_cli/services/file_service.dart';
import 'package:rush_prompt/rush_prompt.dart';

/// Arguments of the [Desugarer._desugar] method. This class is used instead of
/// directly passing required args to that method because when running a method
/// in an [Isolate], we can only pass one arg to it.
class _DesugarArgs {
  final FileService fs;
  final String input;
  final String output;
  final RushYaml rushYaml;
  final RushLock? rushLock;

  _DesugarArgs({
    required this.fs,
    required this.input,
    required this.output,
    required this.rushYaml,
    required this.rushLock,
  });
}

class Desugarer {
  final FileService fs;
  final RushYaml _rushYaml;

  Desugarer(this.fs, this._rushYaml);

  /// Desugars the extension files and dependencies making them compatible with
  /// Android API level < 26.
  Future<void> run(BuildStep step, RushLock? rushLock) async {
    final shouldDesugarDeps = _rushYaml.desugar?.deps ?? false;
    final implDeps = shouldDesugarDeps
        ? _depsToBeDesugared(BuildUtils.getDepJarPaths(
            fs.cwd, _rushYaml, DepScope.implement, rushLock))
        : <String>[];

    // Here, all the desugar process' futures are stored for them to get executed
    // in parallel by the [Future.wait] method.
    final desugarFutures = <Future<ProcessResult>>[];

    // This is where all previously desugared deps of the extension are stored.
    // They are reused between builds.
    final desugarStore = Directory(p.join(fs.buildDir, 'files', 'desugar'))
      ..createSync(recursive: true);

    for (final el in implDeps) {
      final output = p.join(desugarStore.path, p.basename(el));
      final args = _DesugarArgs(
        fs: fs,
        input: el,
        output: output,
        rushYaml: _rushYaml,
        rushLock: rushLock,
      );
      desugarFutures.add(compute(_desugar, args));
    }

    // Desugar extension classes
    final classesDir = p.join(fs.buildDir, 'classes');
    desugarFutures.add(compute(
        _desugar,
        _DesugarArgs(
          fs: fs,
          input: classesDir,
          output: classesDir,
          rushYaml: _rushYaml,
          rushLock: rushLock,
        )));

    final results = await Future.wait(desugarFutures);

    final store = ErrWarnStore();
    for (final result in results) {
      store.incErrors(result.store.getErrors);
      store.incWarnings(result.store.getWarnings);
    }
    await BuildUtils.deletePreviouslyLoggedFromBuildBox();

    if (results.any((el) => !el.success)) {
      throw Exception();
    }
  }

  /// Returns a list of extension dependencies that are to be desugared.
  List<String> _depsToBeDesugared(List<String> deps) {
    final res = <String>[];
    final store = Directory(p.join(fs.buildDir, 'files', 'desugar'))
      ..createSync(recursive: true);

    for (final el in deps) {
      final depDes = File(p.join(store.path, p.basename(el)));
      final depOrig = File(el);

      // Add the dep if it isn't already desugared
      if (!depDes.existsSync()) {
        res.add(depOrig.path);
        continue;
      }

      // Add the dep if it's original file is modified
      final isModified =
          depOrig.lastModifiedSync().isAfter(depDes.lastModifiedSync());
      if (isModified) {
        res.add(depOrig.path);
      }
    }

    return res;
  }

  /// Desugars the specified JAR file or a directory of class files.
  static Future<ProcessResult> _desugar(_DesugarArgs args) async {
    final desugarJar = p.join(args.fs.toolsDir, 'other', 'desugar.jar');

    final classpath = BuildUtils.classpathStringForDeps(
        args.fs, args.rushYaml, args.rushLock);

    final argFile = () {
      final rtJar = p.join(args.fs.toolsDir, 'other', 'rt.jar');

      final contents = <String>[];
      contents
        // emits META-INF/desugar_deps
        ..add('--emit_dependency_metadata_as_needed')
        // Rewrites try-with-resources statements
        ..add('--desugar_try_with_resources_if_needed')
        ..add('--copy_bridges_from_classpath')
        ..addAll(['--bootclasspath_entry', '\'$rtJar\''])
        ..addAll(['--input', '\'${args.input}\''])
        ..addAll(['--output', '\'${args.output}\'']);

      classpath.split(CmdUtils.cpSeparator()).forEach((el) {
        contents.addAll(['--classpath_entry', '\'$el\'']);
      });

      final file = File(p.join(args.fs.buildDir, 'files', 'desugar',
          p.basenameWithoutExtension(args.input) + '.rsh'));

      file.writeAsStringSync(contents.join('\n'));

      return file;
    }();

    final cmdArgs = <String>[];
    cmdArgs
      ..add('java')
      ..addAll(['-cp', desugarJar])
      ..add('com.google.devtools.build.android.desugar.Desugar')
      ..add('@${p.basename(argFile.path)}');

    // Changing the working directory to arg file's parent dir because the
    // desugar.jar doesn't allow the use of `:` in file path which is a common
    // char in Windows paths.
    final result = await ProcessStreamer.stream(cmdArgs, args.fs.cwd,
        workingDirectory: Directory(p.dirname(argFile.path)),
        trackPreviouslyLogged: true);

    if (!result.success) {
      throw Exception();
    }

    argFile.deleteSync();
    return result;
  }
}
