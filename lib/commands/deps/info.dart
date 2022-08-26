import 'package:get_it/get_it.dart';
import 'package:hive/hive.dart';
import 'package:path/path.dart' as p;
import 'package:rush_cli/commands/rush_command.dart';
import 'package:rush_cli/resolver/artifact.dart';
import 'package:rush_cli/services/file_service.dart';

class InfoSubCommand extends RushCommand {
  final FileService _fs = GetIt.I<FileService>();

  @override
  String get description =>
      'Prints the dependency graph of the current extension project.';

  @override
  String get name => 'info';

  @override
  Future<void> run() async {
    Hive
      ..init(p.join(_fs.cwd, '.rush'))
      ..registerAdapter(ArtifactAdapter())
      ..registerAdapter(ScopeAdapter());

    final remoteDepIndex = await Hive.openBox<Artifact>('dep-index');
    final remoteDeps = remoteDepIndex.values.toList();

    // TODO: Colorize the output + print additional info like dep scope, etc.
    final graph = <String>{
      for (final dep in remoteDeps)
        _printGraph(remoteDeps, dep, dep == remoteDeps.last)
    }.join();

    print(p.basename(_fs.cwd) + newLine + graph);
  }

  static const String newLine = '\n';
  static const int branchGap = 3;

  String _printGraph(
    List<Artifact> depList,
    Artifact dep,
    bool isLast, [
    String initial = '',
  ]) {
    String connector = initial;
    connector += isLast ? Connector.lastSibling : Connector.sibling;
    connector += Connector.horizontal * branchGap;

    connector += dep.dependencies.isNotEmpty
        ? Connector.childDeps
        : Connector.horizontal;
    connector +=
        Connector.empty + dep.coordinate + ' (${dep.scope.name})' + newLine;

    for (final el in dep.dependencies) {
      final newInitial = initial +
          (isLast ? Connector.empty : Connector.vertical) +
          Connector.empty * branchGap;
      connector +=
          _printGraph(depList, el, el == dep.dependencies.last, newInitial);
    }

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
