import 'package:args/command_runner.dart';
import 'package:get_it/get_it.dart';
import 'package:path/path.dart' as p;
import 'package:rush_cli/src/services/libs_service.dart';
import 'package:tint/tint.dart';

import 'package:rush_cli/src/config/config.dart';
import 'package:rush_cli/src/resolver/artifact.dart';
import 'package:rush_cli/src/services/file_service.dart';
import 'package:rush_cli/src/services/logger.dart';

class TreeSubCommand extends Command<int> {
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
    final libService = GetIt.I<LibService>();

    final remoteExtDepIndex =
        await libService.extensionDependencies(config, includeLocal: false);
    final requiredRemoteDeps = remoteExtDepIndex
        .where((el) =>
            config.runtimeDeps.contains(el.coordinate) ||
            config.comptimeDeps.contains(el.coordinate))
        .toList(growable: true);

    _lgr.log(p.basename(_fs.cwd).cyan().bold());

    // Print local deps first
    final runtimeLocal = _localDepGraph(
      config.runtimeDeps.where(
          (el) => p.extension(el) == '.jar' || p.extension(el) == '.aar'),
      false,
      remoteExtDepIndex.isEmpty,
    );
    if (runtimeLocal.isNotEmpty) {
      _lgr.log(runtimeLocal);
    }

    final comptimeLocal = _localDepGraph(
      config.comptimeDeps.where(
          (el) => p.extension(el) == '.jar' || p.extension(el) == '.aar'),
      true,
      remoteExtDepIndex.isEmpty,
    );
    if (comptimeLocal.isNotEmpty) {
      _lgr.log(comptimeLocal);
    }

    final remoteDepsGraph = <String>{
      for (final dep in requiredRemoteDeps)
        _remoteDepsGraph(
          dep,
          config,
          remoteExtDepIndex,
          isLast: dep == requiredRemoteDeps.last,
        )
    }.join();
    _lgr.log(remoteDepsGraph);

    return 0;
  }

  String _localDepGraph(
      Iterable<String> deps, bool isComptime, bool noRemoteDeps) {
    final graph = <String>[];
    for (final dep in deps) {
      final isLast = dep == deps.last && noRemoteDeps;
      var branch = isLast ? Connector.lastSibling : Connector.sibling;
      branch += Connector.horizontal * (_branchGap + 1) + Connector.empty;
      if (isComptime) {
        branch += dep.blue() + ' (comptime, local)'.grey();
      } else {
        branch += dep.green() + ' (runtime, local)'.grey();
      }
      graph.add(branch);
    }
    return graph.join('\n');
  }

  static const String _newLine = '\n';
  static const int _branchGap = 2;

  final alreadyPrinted = <Artifact>{};

  String _remoteDepsGraph(
    Artifact artifact,
    Config config,
    List<Artifact> extDepIndex, {
    required bool isLast,
    String prefix = '',
  }) {
    String connector = prefix;
    connector += isLast ? Connector.lastSibling : Connector.sibling;
    connector += Connector.horizontal * _branchGap;

    final hasDeps = artifact.dependencies.isNotEmpty;

    final isPrinted = alreadyPrinted.any((el) =>
        el.coordinate == artifact.coordinate && el.scope == artifact.scope);
    connector +=
        hasDeps && !isPrinted ? Connector.childDeps : Connector.horizontal;
    connector += Connector.empty;

    if (artifact.scope == Scope.runtime) {
      connector += artifact.groupId.green() +
          ':'.grey() +
          artifact.artifactId.green() +
          ':'.grey() +
          artifact.version.toString().green() +
          ' (runtime)'.grey();
    } else {
      connector += artifact.groupId.blue() +
          ':'.grey() +
          artifact.artifactId.blue() +
          ':'.grey() +
          artifact.version.toString().blue() +
          ' (comptime)'.grey();
    }

    if (isPrinted && hasDeps) {
      connector = connector.italic() + ' *'.grey().italic();
    }
    connector += _newLine;

    if (isPrinted) {
      return connector;
    }

    for (final dep in artifact.dependencies) {
      final newPrefix = prefix +
          (isLast ? Connector.empty : Connector.vertical) +
          Connector.empty * _branchGap;
      final depArtifact =
          extDepIndex.firstWhere((element) => element.coordinate == dep);
      connector += _remoteDepsGraph(
        depArtifact,
        config,
        extDepIndex,
        isLast: dep == artifact.dependencies.last,
        prefix: newPrefix,
      );
    }

    alreadyPrinted.add(artifact);
    return connector;
  }
}

class Connector {
  static final sibling = '├'.grey();
  static final lastSibling = '└'.grey();
  static final childDeps = '┬'.grey();
  static final horizontal = '─'.grey();
  static final vertical = '│'.grey();
  static final empty = ' '.grey();
}
