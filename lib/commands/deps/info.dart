import 'package:get_it/get_it.dart';
import 'package:hive/hive.dart';
import 'package:path/path.dart' as p;
import 'package:rush_cli/services/logger.dart';
import 'package:tint/tint.dart';

import '../../commands/rush_command.dart';
import '../../config/rush_yaml.dart';
import '../../resolver/artifact.dart';
import '../../services/file_service.dart';

class InfoSubCommand extends RushCommand {
  final _fs = GetIt.I<FileService>();
  final _lgr = GetIt.I<Logger>();

  @override
  String get description =>
      'Prints the dependency graph of the current extension project.';

  @override
  String get name => 'info';

  @override
  Future<int> run() async {
    Hive.init(p.join(_fs.cwd, '.rush'));
    final rushYaml = await RushYaml.load(_fs.configFile, _lgr);
    if (rushYaml == null) {
      _lgr.err('Failed to load the config file rush.yaml');
      return 1;
    }

    final depsBox = await Hive.openBox<Artifact>('deps');
    final remoteDeps = depsBox.values.toList();
    final directDeps = remoteDeps.where((el) =>
        rushYaml.runtimeDeps.contains(el.coordinate) ||
        rushYaml.comptimeDeps.contains(el.coordinate));

    // TODO: Colorize the output + print additional info like dep scope, etc.
    final graph = <String>{
      for (final dep in directDeps)
        _printGraph(remoteDeps, dep, dep == directDeps.last)
    }.join();

    _lgr.log(p.basename(_fs.cwd) + newLine + graph);
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
    connector += Connector.empty +
        dep.coordinate.replaceAll(':', ':'.brightBlack()) +
        ' (${dep.scope.name})'.brightBlack() +
        (isPrinted && dep.dependencies.isNotEmpty ? ' (*)' : '').brightBlack() +
        newLine;

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
