import 'dart:math';

import 'package:hive/hive.dart';
import 'package:collection/collection.dart';

import 'package:get_it/get_it.dart';
import 'package:rush/src/services/file_service.dart';

part 'artifact.g.dart';

@HiveType(typeId: 1)
enum Scope {
  @HiveField(0)
  compile('compile'),

  @HiveField(1)
  runtime('runtime'),

  // We don't handle dependencies with the following scopes.
  @HiveField(2)
  provided('provided'),

  @HiveField(3)
  test('test'),

  @HiveField(4)
  system('system'),

  @HiveField(5)
  import('import');

  final String _name;
  const Scope(this._name);

  @override
  String toString() => _name;
}

extension ScopeExtension on String {
  Scope toScope() {
    return Scope.values.singleWhere((el) => el.toString() == this);
  }
}

@HiveType(typeId: 2)
class Artifact {
  @HiveField(0)
  String coordinate;

  @HiveField(1)
  Scope scope;

  @HiveField(2)
  final String artifactFile;

  @HiveField(3)
  final String? sourcesJar;

  @HiveField(4)
  List<String> dependencies;

  @HiveField(5)
  final String packaging;

  Artifact({
    required this.coordinate,
    required this.scope,
    required this.artifactFile,
    required this.sourcesJar,
    required this.dependencies,
    required this.packaging,
  });

  String get classesJar {
    if (packaging == 'jar') {
      return artifactFile;
    }

    if (packaging == 'aar') {
      return GetIt.I<FileService>()
          .resourceFromExtractedAar(artifactFile, 'classes.jar')
          .path;
    }

    // TODO: Take a look here
    throw Exception('Unexpected packaging ($packaging) for $coordinate');
  }

  Version get version => Version.from(coordinate.split(':')[2]);

  String get groupId => coordinate.split(':')[0];

  String get artifactId => coordinate.split(':')[1];

  bool get isMavenArtifact => coordinate.split(':').length >= 3;

  String get groupAndArtifactId => '$groupId:$artifactId';

  Set<String> classpathJars(Iterable<Artifact> artifactIndex) {
    return {
      classesJar,
      ...dependencies
          .map((dependency) {
            final artifact = artifactIndex
                .firstWhereOrNull((el) => el.coordinate == dependency);
            return artifact?.classpathJars(artifactIndex);
          })
          .whereNotNull()
          .flattened
          .toSet()
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Artifact &&
          coordinate == other.coordinate &&
          scope == other.scope;

  @override
  int get hashCode => Object.hash(coordinate, scope);

  @override
  String toString() => coordinate;
}

@HiveType(typeId: 3)
class Version implements Comparable<Version> {
  @HiveField(0)
  String _versionStr;

  @HiveField(1)
  final List<String> _elements;

  @HiveField(2)
  String? _originalVersionStr;

  Version(this._versionStr, this._originalVersionStr)
      : _elements = _versionStr.trim().split('.') {
    _versionStr = _versionStr.trim();
    _originalVersionStr ??= _versionStr;
  }

  Version.from(String version, {String? originalVersion})
      : this(version, originalVersion);

  int _stringOrNumComparison(String a, String b) {
    final aNum = int.tryParse(a);
    final bNum = int.tryParse(b);
    if (aNum != null && bNum != null) {
      return aNum.compareTo(bNum);
    } else {
      return a.compareTo(b);
    }
  }

  @override
  String toString() => _versionStr;

  @override
  int compareTo(Version other) {
    if (_versionStr == other._versionStr) return 0;

    final minLength = min(_elements.length, other._elements.length);
    for (var i = 0; i < minLength - 1; i++) {
      final a = _elements[i];
      final b = other._elements[i];
      if (a != b) {
        return _stringOrNumComparison(a, b);
      }
    }

    final a = _elements[minLength - 1];
    final b = other._elements[minLength - 1];
    if (a != b) {
      return _stringOrNumComparison(a, b);
    }

    if (_elements.length > other._elements.length) {
      return 1;
    } else if (_elements.length < other._elements.length) {
      return -1;
    } else {
      return 0;
    }
  }
}
