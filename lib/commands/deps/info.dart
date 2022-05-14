import 'package:hive/hive.dart';
import 'package:collection/collection.dart';
import 'package:path/path.dart' as p;
import 'package:rush_cli/commands/build/hive_adapters/remote_dep.dart';
import 'package:rush_cli/commands/rush_command.dart';
import 'package:rush_cli/services/file_service.dart';

class InfoSubCommand extends RushCommand {
  final FileService _fs;

  InfoSubCommand(this._fs);

  @override
  String get description =>
      'Prints the dependency graph of the current extension project.';

  @override
  String get name => 'info';

  @override
  Future<void> run() async {
    Hive
      ..init(p.join(_fs.cwd, '.rush'))
      ..registerAdapter(RemoteDepAdapter());

    final remoteDepIndex = await Hive.openBox<RemoteDep>('index');
    final directDeps = remoteDepIndex.values.where((el) => el.isDirectDep);

    // TODO: Colorize the output + print additional info like dep scope, etc.
    final graph = {
      for (final dep in directDeps)
        _printGraph(remoteDepIndex.values.toSet(), dep, dep == directDeps.last)
    }.join();

    print(p.basename(_fs.cwd) + newLine + graph);
  }

  static const String newLine = '\n';
  static const int branchGap = 3;

  String _printGraph(
    Set<RemoteDep> remoteDepIndex,
    RemoteDep dep,
    bool isLast, [
    String initial = '',
  ]) {
    String connector = initial;
    connector += isLast ? Connector.lastSibling : Connector.sibling;
    connector += Connector.horizontal * branchGap;

    connector += dep.depCoordinates.isNotEmpty
        ? Connector.childDeps
        : Connector.horizontal;
    connector += Connector.empty + dep.coordinate + newLine;

    for (final el in dep.depCoordinates) {
      final remoteDep =
          remoteDepIndex.firstWhereOrNull((e) => e.coordinate == el);

      final newInitial = initial +
          (isLast ? Connector.empty : Connector.vertical) +
          Connector.empty * branchGap;

      if (remoteDep != null) {
        connector += _printGraph(remoteDepIndex, remoteDep,
            el == dep.depCoordinates.last, newInitial);
      }
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
