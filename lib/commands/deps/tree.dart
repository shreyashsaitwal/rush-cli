import 'package:get_it/get_it.dart';
import 'package:path/path.dart' as p;
import 'package:rush_cli/services/libs_service.dart';
import 'package:tint/tint.dart';

import 'package:rush_cli/commands/rush_command.dart';
import 'package:rush_cli/config/config.dart';
import 'package:rush_cli/resolver/artifact.dart';
import 'package:rush_cli/services/file_service.dart';
import 'package:rush_cli/services/logger.dart';

class TreeSubCommand extends RushCommand {
  final _fs = GetIt.I<FileService>();
  final _lgr = GetIt.I<Logger>();

  @override
  String get description =>
      'Prints the dependency graph of the current extension project.';

  @override
  String get name => 'tree';

  @override
  Future<int> run() async {
    final config = await Config.load(_fs.configFile, _lgr);
    if (config == null) {
      _lgr.err('Failed to load the config file rush.yaml');
      return 1;
    }

    await GetIt.I.isReady<LibService>();

    final remoteDeps = await GetIt.I<LibService>().projectRemoteDepArtifacts();
    final directDeps = remoteDeps.where((el) =>
        config.runtimeDeps.contains(el.coordinate) ||
        config.comptimeDeps.contains(el.coordinate));

    // TODO: Colorize the output + print additional info like dep scope, etc.
    final graph = <String>{
      for (final dep in directDeps)
        _printGraph(remoteDeps, dep, dep == directDeps.last)
    }.join();

    _lgr.log(p.basename(_fs.cwd).cyan().bold() + newLine + graph);
    return 0;
  }

  static const String newLine = '\n';
  static const int branchGap = 2;

  final alreadyPrinted = <Artifact>{};

  String _printGraph(
    Iterable<Artifact> depList,
    Artifact dep,
    bool isLast, [
    String prefix = '',
  ]) {
    String connector = prefix;
    connector += isLast ? Connector.lastSibling : Connector.sibling;
    connector += Connector.horizontal * branchGap;

    final isPrinted = alreadyPrinted
        .any((el) => el.coordinate == dep.coordinate && el.scope == dep.scope);
    connector += dep.dependencies.isNotEmpty && !isPrinted
        ? Connector.childDeps
        : Connector.horizontal;
    connector += Connector.empty;

    if (dep.scope == Scope.runtime) {
      connector += dep.groupId.green() +
          ':'.brightBlack() +
          dep.artifactId.green() +
          ':'.brightBlack() +
          dep.version.versionSpec.green() +
          ' (runtime)'.brightBlack();
    } else {
      connector += dep.groupId.blue() +
          ':'.brightBlack() +
          dep.artifactId.blue() +
          ':'.brightBlack() +
          dep.version.versionSpec.blue() +
          ' (comptime)'.brightBlack();
    }

    if (isPrinted && dep.dependencies.isNotEmpty) {
      connector = connector.italic() + ' *'.brightBlack().italic();
    }
    connector += newLine;

    if (isPrinted) {
      return connector;
    }

    for (final el in dep.dependencies) {
      final newPrefix = prefix +
          (isLast ? Connector.empty : Connector.vertical) +
          Connector.empty * branchGap;
      final artifact =
          depList.firstWhere((element) => element.coordinate == el);
      connector += _printGraph(
          depList, artifact, el == dep.dependencies.last, newPrefix);
    }

    alreadyPrinted.add(dep);
    return connector;
  }
}

class Connector {
  static final sibling = '├'.brightBlack();
  static final lastSibling = '└'.brightBlack();
  static final childDeps = '┬'.brightBlack();
  static final horizontal = '─'.brightBlack();
  static final vertical = '│'.brightBlack();
  static final empty = ' '.brightBlack();
}
