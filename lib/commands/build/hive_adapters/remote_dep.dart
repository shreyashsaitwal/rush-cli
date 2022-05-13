import 'package:hive/hive.dart';
import 'package:path/path.dart' as p;
import 'package:resolver/resolver.dart';

part 'remote_dep.g.dart';

@HiveType(typeId: 1)
class RemoteDep {
  @HiveField(0)
  final String coordinate;

  @HiveField(1)
  final String cacheDir;

  @HiveField(2)
  final String _scope;

  @HiveField(3)
  final List<String> depCoordinates;

  @HiveField(4)
  final String packaging;

  @HiveField(5)
  final bool isDirectDep;

  RemoteDep(this.coordinate, this.cacheDir, this._scope, this.depCoordinates,
      this.packaging, this.isDirectDep);

  String get groupId => coordinate.split(':')[0];
  String get artifactId => coordinate.split(':')[1];
  String get version => coordinate.split(':')[2];

  DependencyScope get scope {
    switch (_scope) {
      case 'compile':
        return DependencyScope.compile;
      case 'runtime':
        return DependencyScope.runtime;
      case 'provided':
        return DependencyScope.provided;
      case 'test':
        return DependencyScope.test;
      default:
        return DependencyScope.compile;
    }
  }

  String get artifactFile => p.joinAll(
        [
          cacheDir,
          ...groupId.split('.'),
          artifactId,
          version,
          '$artifactId-$version.$packaging'
        ],
      );

  String get sourcesFile => p.joinAll(
        [
          cacheDir,
          ...groupId.split('.'),
          artifactId,
          version,
          '$artifactId-$version-sources.jar'
        ],
      );

  @override
  String toString() => '''
RemoteDepIndex(
  coordinate: $coordinate,
  scope: $_scope,
)''';
}
