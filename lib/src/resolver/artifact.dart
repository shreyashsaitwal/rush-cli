import 'dart:math';

import 'package:hive/hive.dart';
import 'package:path/path.dart' as p;
import 'package:collection/collection.dart';
import 'package:xrange/xrange.dart';

import 'package:rush_cli/src/utils/file_extension.dart';

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
      final baseDir = p
          .join(
              p.dirname(artifactFile), p.basenameWithoutExtension(artifactFile))
          .asDir(true);
      final jar = p.join(baseDir.path, 'classes.jar').asFile();
      return jar.path;
    }

    // TODO: Take a look here
    throw Exception('Unexpected packaging ($packaging) for $coordinate');
  }

  Version get version => Version.from(coordinate.split(':')[2]);

  String get groupId => coordinate.split(':')[0];

  String get artifactId => coordinate.split(':')[1];

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

  /// Original version string as defined in the pom.xml of the artifact.
  String get originalVersionSpec => _originalVersionStr!;

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

  static RegExp rangeRegex =
      RegExp(r'([\[\(])(-?∞?[^,]*)(\,?|\.\.)?(-?∞?[^,]*)?([\]\)])');

  // FIXME: Currently, we are not handling ranges like this: [1,2),(4,6]. Although,
  // they are not very common (I have never seen them in the wild), we should
  // still handle them.
  // Below copy-pasta sauce: https://stackoverflow.com/a/45627598/12401482 :)
  Range<Version>? get range {
    _originalVersionStr ??= _versionStr;

    if (!rangeRegex.hasMatch(_originalVersionStr!)) {
      return null;
    }

    final matches = rangeRegex.allMatches(_originalVersionStr!).first;
    if (rangeRegex.hasMatch(_originalVersionStr!)) {
      final lowerBoundEndpoint = matches.group(2);
      final separator = matches.group(3);
      final upperBoundEndpoint = matches.group(4);

      // Singleton case (e.g. [1.0.0])
      if (separator == null) {
        return Range.singleton(Version.from(lowerBoundEndpoint!));
      }

      if (lowerBoundEndpoint == null && upperBoundEndpoint == null) {
        return Range.all();
      }

      final lowerBoundInclusive = matches.group(1)! == '[';
      final upperBoundInclusive = matches.group(5)! == ']';

      // Lower infinity case (e.g. [, 1.0.0])
      if (lowerBoundEndpoint == null || lowerBoundEndpoint == '') {
        if (upperBoundInclusive) {
          return Range.atMost(Version.from(upperBoundEndpoint!));
        } else {
          return Range.lessThan(Version.from(upperBoundEndpoint!));
        }
      }

      // Upper infinity case (e.g. [1.0.0, ])
      else if (upperBoundEndpoint == null || upperBoundEndpoint == '') {
        if (lowerBoundInclusive) {
          return Range.atLeast(Version.from(lowerBoundEndpoint));
        } else {
          return Range.greaterThan(Version.from(lowerBoundEndpoint));
        }
      }

      // Non infinity case (e.g. [1.0.0, 2.0.0])
      if (lowerBoundInclusive) {
        if (upperBoundInclusive) {
          return Range.closed(Version.from(lowerBoundEndpoint),
              Version.from(upperBoundEndpoint));
        } else {
          return Range.closedOpen(Version.from(lowerBoundEndpoint),
              Version.from(upperBoundEndpoint));
        }
      } else {
        if (upperBoundInclusive) {
          return Range.openClosed(Version.from(lowerBoundEndpoint),
              Version.from(upperBoundEndpoint));
        } else {
          return Range.open(Version.from(lowerBoundEndpoint),
              Version.from(upperBoundEndpoint));
        }
      }
    } else {
      throw Exception('${_originalVersionStr!} is not a valid range notation');
    }
  }

  @override
  String toString() => _versionStr;

  @override
  int compareTo(Version other) {
    if (_versionStr == other._versionStr) return 0;

    final minLenght = min(_elements.length, other._elements.length);
    for (var i = 0; i < minLenght - 1; i++) {
      final a = _elements[i];
      final b = other._elements[i];
      if (a != b) {
        return _stringOrNumComparison(a, b);
      }
    }

    final a = _elements[minLenght - 1];
    final b = other._elements[minLenght - 1];
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
