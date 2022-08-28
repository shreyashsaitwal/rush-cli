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
    Hive.init(p.join(_fs.cwd, '.rush'));

    final depsBox = await Hive.openBox<Artifact>('deps');
    final remoteDeps = depsBox.values.toList();

    // TODO: Colorize the output + print additional info like dep scope, etc.
    final graph = <String>{
      for (final dep in remoteDeps)
        _printGraph(remoteDeps, dep, dep == remoteDeps.last)
    }.join();

    print(p.basename(_fs.cwd) + newLine + graph);
  }

  static const String newLine = '\n';
  static const int branchGap = 2;

  final alreadyPrinted = <Artifact>{};

  String _printGraph(
    List<Artifact> depList,
    Artifact dep,
    bool isLast, [
    String prefix = '',
  ]) {
    String connector = prefix;
    connector += isLast ? Connector.lastSibling : Connector.sibling;
    connector += Connector.horizontal * branchGap;

    final printed = alreadyPrinted
        .any((el) => el.coordinate == dep.coordinate && el.scope == dep.scope);
    connector += dep.dependencies.isNotEmpty && !printed
        ? Connector.childDeps
        : Connector.horizontal;
    connector += Connector.empty + dep.coordinate +' (${dep.scope.name})' +
        (printed && dep.dependencies.isNotEmpty ? ' (*)' : '') + newLine;

    if (printed) {
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
