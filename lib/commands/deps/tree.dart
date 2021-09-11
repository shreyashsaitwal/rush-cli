import 'dart:io';

import 'package:dart_console/dart_console.dart';
import 'package:path/path.dart' as p;
import 'package:rush_cli/commands/rush_command.dart';
import 'package:rush_cli/models/rush_lock/rush_lock.dart';
import 'package:rush_cli/models/rush_yaml/rush_yaml.dart';
import 'package:rush_cli/services/file_service.dart';
import 'package:rush_cli/utils/cmd_utils.dart';
import 'package:rush_prompt/rush_prompt.dart';

class DepsTreeCommand extends RushCommand {
  final FileService _fs;

  DepsTreeCommand(this._fs);

  @override
  String get description =>
      'Prints the dependency tree of the current project.';

  @override
  String get name => 'tree';

  @override
  void run() {
    final rushLock = CmdUtils.loadRushLock(_fs.cwd);
    final rushYaml = CmdUtils.loadRushYaml(_fs.cwd);

    final localDeps =
        rushYaml.deps?.where((el) => !el.value().contains(':')) ?? [];
    if (rushLock == null && localDeps.isEmpty) {
      Logger.log(LogType.note, 'This project doesn\'t have any dependency.');
      exit(0);
    }

    final console = Console();
    console.writeLine(p.basename(_fs.cwd));

    for (final el in localDeps) {
      final isLast = rushLock == null && localDeps.last == el;
      console
        ..setForegroundColor(ConsoleColor.brightBlack)
        ..write(isLast ? '└──── ' : '├──── ')
        ..resetColorAttributes()
        ..write('deps/');

      if (el.scope() == DepScope.implement) {
        console.setTextStyle(underscore: true);
      }

      console
        ..setForegroundColor(ConsoleColor.yellow)
        ..writeLine(el.value())
        ..resetColorAttributes()
        ..setTextStyle(underscore: false);
    }

    if (rushLock != null) {
      final f = rushLock.resolvedArtifacts.where((el) => el.isDirect).toList();
      for (var i = 0; i < f.length; i++) {
        _buildTree(console, f[i], rushLock, i + 1 == f.length);
      }
    }

    console
      ..writeLine('\n')
      ..setForegroundColor(ConsoleColor.yellow)
      ..write('artifactID')
      ..resetColorAttributes()
      ..writeLine('  This is a compile-time dependency');

    console
      ..setForegroundColor(ConsoleColor.yellow)
      ..setTextStyle(underscore: true)
      ..write('artifactID')
      ..resetColorAttributes()
      ..setTextStyle(underscore: false)
      ..writeLine('  This is a runtime + compile-time dependency');

    console
      ..setForegroundColor(ConsoleColor.brightBlack)
      ..write('{ ')
      ..setForegroundColor(ConsoleColor.white)
      ..write('x')
      ..setForegroundColor(ConsoleColor.cyan)
      ..write(' -> ')
      ..setForegroundColor(ConsoleColor.brightWhite)
      ..write('y')
      ..setForegroundColor(ConsoleColor.brightBlack)
      ..write(' }')
      ..resetColorAttributes()
      ..writeLine('  This dependency was up/down-graded from version "x" to "y"');
  }

  void _buildTree(
    Console console,
    Artifact artifact,
    RushLock rushLock,
    bool isLast, {
    int depth = 0,
  }) {
    var depthStr = '│    ' * depth;

    if (isLast) {
      depthStr += '└──── ';
    } else {
      depthStr += '├──── ';
    }
    console
      ..setForegroundColor(ConsoleColor.brightBlack)
      ..write(depthStr)
      ..resetColorAttributes();

    if (artifact is SkippedArtifact) {
      final splitted = artifact.coordinate.split(':');
      _printGrpArtId(
          console, splitted[0], splitted[1], artifact.scope == 'runtime');
      console
        ..setForegroundColor(ConsoleColor.cyan)
        ..write(':')
        ..setForegroundColor(ConsoleColor.brightBlack)
        ..write('{ ')
        ..setForegroundColor(ConsoleColor.white)
        ..write(splitted[2])
        ..setForegroundColor(ConsoleColor.cyan)
        ..write(' -> ')
        ..setForegroundColor(ConsoleColor.brightWhite)
        ..write(artifact.availableVer)
        ..setForegroundColor(ConsoleColor.brightBlack)
        ..writeLine(' }')
        ..resetColorAttributes();
    }

    if (artifact is ResolvedArtifact) {
      final splitted = artifact.coordinate.split(':');
      _printGrpArtId(
          console, splitted[0], splitted[1], artifact.scope == 'runtime');
      console
        ..setForegroundColor(ConsoleColor.cyan)
        ..write(':')
        ..setForegroundColor(ConsoleColor.white)
        ..writeLine(splitted[2])
        ..resetColorAttributes();

      for (final el in artifact.deps) {
        Artifact dep;
        try {
          dep = rushLock.resolvedArtifacts
              .firstWhere((element) => element.coordinate == el);
        } catch (_) {
          try {
            dep = rushLock.skippedArtifacts
                .firstWhere((element) => element.coordinate == el);
          } catch (e) {
            continue;
          }
        }
        _buildTree(console, dep, rushLock, el == artifact.deps.last,
            depth: depth + 1);
      }
    }
  }

  void _printGrpArtId(
      Console console, String group, String artifactId, bool isRuntime) {
    console
      ..write(group)
      ..setForegroundColor(ConsoleColor.cyan)
      ..write(':');

    if (isRuntime) {
      console.setTextStyle(underscore: true);
    }

    console
      ..setForegroundColor(ConsoleColor.yellow)
      ..write(artifactId)
      ..setTextStyle(underscore: false);
  }

  // final s = '''
  // work-runtime == This is a compile-time dependency
  // work-runtime == This is a runtime + compile-time dependency

  // { x -> y } == This dependency was up/down-graded from version x to version y.
  // ''';
}
