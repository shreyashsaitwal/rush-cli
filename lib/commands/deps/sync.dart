import 'dart:io';

import 'package:collection/collection.dart';
import 'package:hive/hive.dart';
import 'package:path/path.dart' as p;
import 'package:rush_cli/commands/build/hive_adapters/build_box.dart';
import 'package:rush_cli/commands/build/tools/executor.dart';
import 'package:rush_cli/commands/build/utils/build_utils.dart';
import 'package:rush_cli/commands/rush_command.dart';
import 'package:rush_cli/models/rush_lock/rush_lock.dart';
import 'package:rush_cli/services/file_service.dart';
import 'package:rush_cli/templates/intellij_files.dart';
import 'package:rush_cli/utils/cmd_utils.dart';
import 'package:rush_prompt/rush_prompt.dart';

class DepsSyncCommand extends RushCommand {
  final FileService _fs;

  DepsSyncCommand(this._fs);

  @override
  String get description =>
      'Syncs the remote dependencies of the current project.';

  @override
  String get name => 'sync';

  @override
  Future<RushLock?> run({bool syncIdeaFiles = true}) async {
    final startTime = DateTime.now();
    final rushYaml = CmdUtils.loadRushYaml(_fs.cwd);

    final containsRemoteDeps =
        rushYaml.deps?.any((el) => el.value().contains(':')) ?? false;
    final lockFile = File(p.join(_fs.cwd, '.rush', 'rush.lock'));

    if (!containsRemoteDeps) {
      if (lockFile.existsSync()) {
        lockFile.deleteSync();
      }
      return null;
    }

    final buildBox = await Hive.openBox<BuildBox>('build');

    final step = BuildStep('Resolving dependencies')..init();
    final boxVal = buildBox.getAt(0)!;

    final lastResolvedDeps = boxVal.lastResolvedDeps;
    final currentRemoteDeps = rushYaml.deps
            ?.where((el) => el.value().contains(':'))
            .map((el) => el.value())
            .toList() ??
        <String>[];

    final areDepsUpToDate = DeepCollectionEquality.unordered()
        .equals(lastResolvedDeps, currentRemoteDeps);

    if (!areDepsUpToDate ||
        !lockFile.existsSync() ||
        lockFile.lastModifiedSync().isAfter(boxVal.lastResolution)) {
      try {
        if (lockFile.existsSync()) {
          lockFile.deleteSync();
        }
        await Executor.execResolver(_fs);
      } catch (e) {
        step.finishNotOk();
        BuildUtils.printFailMsg(startTime);
      } finally {
        buildBox
          ..updateLastResolution(DateTime.now())
          ..updateLastResolvedDeps(currentRemoteDeps);
      }
    } else {
      step.log(LogType.info, 'Everything is up-to-date!');
    }

    final RushLock rushLock;
    try {
      rushLock = CmdUtils.loadRushLock(_fs.cwd)!;
    } catch (e) {
      step
        ..log(LogType.erro, e.toString())
        ..finishNotOk();
      BuildUtils.printFailMsg(startTime);
      exit(1);
    }

    if (rushLock.skippedArtifacts.isNotEmpty) {
      step.log(
          LogType.warn,
          'The following dependencies were up/down-graded to the versions that were'
          ' already available as dev-dependencies:');

      final longestCoordLen =
          rushLock.skippedArtifacts.map((el) => el.coordinate).max.length + 1;
      final longestScopeLen =
          rushLock.skippedArtifacts.map((el) => el.scope).max.length;

      for (final el in rushLock.skippedArtifacts) {
        step.log(
            LogType.warn,
            ' ' * 5 +
                '- ${el.coordinate.padRight(longestCoordLen)}  -->  ${el.availableVer}  (${el.scope.padLeft(longestScopeLen)})',
            addPrefix: false);
      }

      step.log(
          LogType.note,
          'If you don\'t want the above artifact(s) to get up/down-graded,'
          ' consider explicitly declaring them in rush.yml');

      if (syncIdeaFiles) {
        for (final el in rushLock.resolvedArtifacts) {
          _updateLibXml(el, rushLock);
        }

        var imlFile = Directory(p.join(_fs.cwd, '.idea'))
            .listSync()
            .whereType<File>()
            .firstWhereOrNull((el) => p.extension(el.path) == '.iml');
        imlFile ??= File(p.join(_fs.cwd, '.idea', p.basename(_fs.cwd) + '.iml'))
          ..createSync(recursive: true);
        imlFile.writeAsStringSync(getIml(p.dirname(imlFile.path)));
      }
    }

    step.finishOk();
    return rushLock;
  }

  void _updateLibXml(ResolvedArtifact artifact, RushLock rushLock) {
    final classes = <String>[];

    if (artifact.type == 'aar') {
      final outputDir = Directory(p.join(
          p.dirname(artifact.path), p.basenameWithoutExtension(artifact.path)))
        ..createSync(recursive: true);

      final classesJarFile = File(p.join(outputDir.path, 'classes.jar'));
      final manifestXml = File(p.join(outputDir.path, 'AndroidManifest.xml'));
      if (!classesJarFile.existsSync()) {
        BuildUtils.unzip(artifact.path, outputDir.path);
      }

      classes
        ..add(classesJarFile.path)
        ..add(manifestXml.path);
    } else {
      classes.add(artifact.path);
    }

    final javadocs = Directory(p.dirname(artifact.path))
        .listSync()
        .whereType<File>()
        .where((el) => el.path.endsWith('javadoc.jar'))
        .map((el) => el.path)
        .toList();

    final sources = Directory(p.dirname(artifact.path))
        .listSync()
        .whereType<File>()
        .where((el) => el.path.endsWith('sources.jar'))
        .map((el) => el.path)
        .toList();

    final name = () {
      final common = artifact.coordinate.replaceAll(':', '-');
      if (artifact.type == 'aar') {
        return 'rush-$common-aar';
      } else {
        return 'rush-$common-jar';
      }
    }();
    final libXml = File(p.join(_fs.cwd, '.idea', 'libraries', '$name.xml'));
    libXml
      ..createSync()
      ..writeAsStringSync(getLibXml(name, classes, javadocs, sources));
  }
}
