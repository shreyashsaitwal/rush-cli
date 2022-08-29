import 'package:get_it/get_it.dart';
import 'package:hive/hive.dart';
import 'package:path/path.dart' as p;

import '../../commands/rush_command.dart';
import '../../config/rush_yaml.dart';
import '../../resolver/artifact.dart';
import '../../services/file_service.dart';

class InfoSubCommand extends RushCommand {
  final FileService _fs = GetIt.I<FileService>();

  @override
  String get description =>
      'Prints the dependency graph of the current extension project.';

  @override
  String get name => 'info';

  @override
  Future<void> run() async {
    Hive.init(p.join(_fs.cwd, '.rush'));
    final rushYaml = await RushYaml.load(_fs.configFile);

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

    print(p.basename(_fs.cwd) + newLine + graph);
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
        dep.coordinate +
        ' (${dep.scope.name})' +
        (isPrinted && dep.dependencies.isNotEmpty ? ' (*)' : '') +
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
  static const String sibling = '├';
  static const String lastSibling = '└';
  static const String childDeps = '┬';
  static const String horizontal = '─';
  static const String vertical = '│';
  static const String empty = ' ';
}
