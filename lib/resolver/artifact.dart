import 'package:hive/hive.dart';
import 'package:path/path.dart' as p;

import '../utils/file_extension.dart';
import '../commands/build/utils.dart';

part 'artifact.g.dart';

@HiveType(typeId: 2)
enum Scope {
  @HiveField(0)
  compile,
  @HiveField(1)
  runtime,

  /// We don't handle dependencies with the below scopes.
  provided,
  test,
  system,
  import,
}

extension ScopeExtension on String {
  Scope toScope() {
    if (this == 'compile') {
      return Scope.compile;
    } else if (this == 'runtime') {
      return Scope.runtime;
    } else if (this == 'provided') {
      return Scope.provided;
    } else if (this == 'test') {
      return Scope.test;
    } else if (this == 'system') {
      return Scope.system;
    } else if (this == 'import') {
      return Scope.import;
    } else {
      throw Exception('Unknown scope: $this');
    }
  }
}

@HiveType(typeId: 1)
class Artifact {
  @HiveField(0)
  final String coordinate;

  @HiveField(1)
  final Scope scope;

  @HiveField(2)
  final String artifactFile;

  @HiveField(3)
  final String? sourceJar;

  @HiveField(4)
  final List<Artifact> dependencies;

  @HiveField(5)
  final bool isAar;

  Artifact({
    required this.coordinate,
    required this.scope,
    required this.artifactFile,
    required this.sourceJar,
    required this.dependencies,
    required this.isAar,
  });

  String get classesJar {
    if (p.extension(artifactFile) == '.bundle') {
      final jarFile = p
          .join(
              artifactFile.replaceRange(artifactFile.length - 7, null, '.jar'))
          .asFile();
      if (jarFile.existsSync()) {
        return jarFile.path;
      }
    } else if (!isAar) {
      return artifactFile;
    }

    final basename = p.basenameWithoutExtension(artifactFile);
    final dist = p.join(p.dirname(artifactFile), basename).asDir(true);
    BuildUtils.unzip(artifactFile, dist.path);
    return p.join(dist.path, 'classes.jar');
  }

  Set<String> classpathJars() {
    final classpath = <String>{classesJar};
    for (final dep in dependencies) {
      classpath.addAll(dep.classpathJars());
    }
    return classpath;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Artifact &&
          coordinate == other.coordinate &&
          scope == other.scope;

  @override
  int get hashCode => Object.hash(coordinate, scope);
}
