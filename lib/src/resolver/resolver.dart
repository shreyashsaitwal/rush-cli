import 'dart:io';

import 'package:collection/collection.dart';
import 'package:crypto/crypto.dart';
import 'package:github/github.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:xml2json/xml2json.dart';

import 'package:rush_cli/src/resolver/artifact.dart';
import 'package:rush_cli/src/resolver/pom.dart';
import 'package:rush_cli/src/utils/file_extension.dart';

class ArtifactMetadata {
  late final String groupId;
  late final String artifactId;
  late final String version;
  late final String classifier;

  ArtifactMetadata(String coordinate) {
    final parts = coordinate.split(':');
    if (parts.length < 3 || parts.length > 4) {
      throw Exception(
          'Invalid artifact coordinate format: $coordinate\nExpected format: <groupId>:<artifactId>:<version>:<classifier?>');
    }
    groupId = parts[0];
    artifactId = parts[1];
    version = parts[2];
    if (parts.length == 4) {
      classifier = parts[3];
    } else {
      classifier = '';
    }
  }

  String _basePath() =>
      p.joinAll([...groupId.split('.'), artifactId, version]).replaceAll(
          '\\', '/');

  String pomPath() =>
      p.join(_basePath(), '$artifactId-$version.pom').replaceAll('\\', '/');

  String artifactPath(String packaging) => p
      .join(_basePath(),
          '$artifactId-$version${classifier.isNotEmpty ? '-$classifier' : ''}.$packaging')
      .replaceAll('\\', '/');

  String sourceJarPath() => p
      .join(_basePath(), '$artifactId-$version-sources.jar')
      .replaceAll('\\', '/');
}

class ArtifactResolver {
  var _mvnRepos = <String>{
    'https://repo1.maven.org/maven2',
    'https://dl.google.com/dl/android/maven2',
    'https://repo.maven.apache.org/maven2',
  };
  final _client = http.Client();

  late final String _localMvnRepo;

  ArtifactResolver({String? localMvnRepo, required Set<String> repos}) {
    if (localMvnRepo != null) {
      _localMvnRepo = localMvnRepo;
    } else if (Platform.isWindows) {
      _localMvnRepo = p
          .join(Platform.environment['UserProfile']!, '.m2', 'repository')
          .asDir(true)
          .path;
    } else {
      _localMvnRepo = p
          .join(Platform.environment['HOME']!, '.m2', 'repository')
          .asDir(true)
          .path;
    }

    // User defined repos should be given priority over the default ones.
    _mvnRepos = {...repos, ..._mvnRepos};
  }

  final _hashTypes = {
    'sha1',
    'md5',
    'sha256',
    'sha512',
  };

  Future<bool> _verifyChecksum(File file, File checksumFile) async {
    final ext = p.extension(checksumFile.path);
    final fileChecksum = await () async {
      if (ext == '.sha1') {
        return sha1.convert(await file.readAsBytes());
      } else if (ext == '.md5') {
        return md5.convert(await file.readAsBytes());
      } else if (ext == '.sha256') {
        return sha256.convert(await file.readAsBytes());
      } else if (ext == '.sha512') {
        return sha512.convert(await file.readAsBytes());
      } else {
        throw Exception('Unsupported checksum type: $ext');
      }
    }();

    final requiredChecksum =
        (await checksumFile.readAsString()).trim().split(RegExp(r'\s+')).first;
    return fileChecksum.toString() == requiredChecksum;
  }

  Future<File?> _fetchFile(String relativeFilePath) async {
    final file = p.join(_localMvnRepo, relativeFilePath).asFile();
    if (await file.exists() && (await file.stat()).size > 0) {
      return file;
    }

    for (final repo in _mvnRepos) {
      final uri = Uri.parse(p.posix.join(repo, relativeFilePath));
      try {
        final response = await _client.get(uri);
        if (response.statusCode == StatusCodes.OK) {
          await file.create(recursive: true);
          await file.writeAsBytes(response.bodyBytes, flush: true);
          break;
        }
        continue;
      } catch (e) {
        Exception('Error while fetching URI: $uri:\n$e');
      }
    }

    if (!await file.exists() || (await file.stat()).size <= 0) {
      return null;
    }

    final isFileChecksum =
        _hashTypes.contains(p.extension(file.path).substring(1));

    if (!isFileChecksum) {
      final checksumPaths = _hashTypes.map((el) => '$relativeFilePath.$el');
      File? checksum;
      for (final path in checksumPaths) {
        final checksumFile = await _fetchFile(path);
        if (checksumFile != null) {
          checksum = checksumFile;
          break;
        }
      }

      if (checksum != null && !await _verifyChecksum(file, checksum)) {
        throw Exception('Checksum verification failed for file: ${file.path}');
      }
    }

    return file;
  }

  void closeHttpConn() {
    _client.close();
  }

  /// For details on how this (roughly) works:
  /// https://maven.apache.org/guides/introduction/introduction-to-the-pom.html#project-interpolation-and-variables
  Version _resolveCoordVersion(
      String coordinate, Pom dependentPom, List<Pom> parentsOfDepPom) {
    final metadata = ArtifactMetadata(coordinate);
    var version = metadata.version == 'null' ? null : metadata.version;
    final error =
        'Could not resolve version `$version` for coordinate: $coordinate as required by ${dependentPom.coordinate}';

    // If the version is defined in a range, pick the upper endpoint if it is
    // upper bounded otherwise pick the lower endpoint for now.
    if (version != null && Version.rangeRegex.hasMatch(version)) {
      final range = Version.from(version).range;
      if (!range!.upperBounded) {
        return Version.from(range.lower!.toString(), originalVersion: version);
      }
      return Version.from(range.upper!.toString(), originalVersion: version);
    }

    // If the version is null, then it might be stored in the [pom] or [parentPom]
    // as a implicit value or as variable.
    version ??= dependentPom.dependencyManagement
        // First, check for this dependency in the same POM's dependencyManagement section.
        .firstWhere(
      (el) {
        return el.artifactId == metadata.artifactId &&
            el.groupId == metadata.groupId;
      },
      // If not found, check in the all parent POM's dependencyManagement section.
      orElse: () {
        if (parentsOfDepPom.isEmpty) {
          throw Exception(error);
        }
        return parentsOfDepPom
            .map((el) => el.dependencyManagement)
            .flattened
            .firstWhere(
          (el) {
            return el.groupId == metadata.groupId &&
                (el.artifactId == metadata.artifactId ||
                    el.artifactId == '${metadata.artifactId}-bom');
          },
          // If still not found, throw an exception.
          orElse: () {
            throw Exception(error);
          },
        );
      },
    ).version!;

    // The below implementation of variable interpolation isn't (probably?) the
    // most correct way to do this, but (I think) should work most of the times.
    // Quote from Maven documentation:
    // "One factor to note is that these variables are processed after inheritance
    //  [...]. This means that if a parent project uses a variable, then its
    //  definition in the child, not the parent, will be the one eventually used."
    // So, maybe, FIXME?

    // If the version is a variable, it will be defined as ${variable}. This variable
    // could be a property or a POM field (we only handle project.version field).
    if (version.startsWith('\${')) {
      final variable = version.substring(2, version.length - 1);

      // TODO: Extract this and the similar groupId interpolation stuff in
      // [resolveArtifact] method to a separate method.
      final projectField = ['project.version', 'pom.version', '.version'];
      if (projectField.contains(variable)) {
        return Version.from(dependentPom.version!);
      }

      // When the variable is a POM property.
      final properties = dependentPom.properties;
      for (final el in parentsOfDepPom) {
        properties.addAll(el.properties);
      }

      if (properties.containsKey(variable)) {
        return Version.from(properties[variable]!.toString());
      } else {
        throw Exception(error);
      }
    }

    // Version is likely a normal version literal.
    return Version.from(version);
  }

  Future<List<Pom>> _resolvePomAndParents(String? coordinate) async {
    if (coordinate == null) {
      return const [];
    }

    final metadata = ArtifactMetadata(coordinate);
    final pomFile = await _fetchFile(metadata.pomPath());
    if (pomFile == null) {
      throw Exception(
          'Unable to find POM file for $coordinate in any of the available Maven repositories.');
    }

    final Pom pom;
    try {
      pom = Pom.fromXml(await pomFile.readAsString());
    } on Xml2JsonException catch (e) {
      throw Exception('Error while parsing POM file for $coordinate:\n$e');
    }

    pom.groupId ??= metadata.groupId;
    pom.version ??= metadata.version;

    final parentPoms = await _resolvePomAndParents(pom.parent?.coordinate);

    // Deps of type imports are POM files who's dependencies we need to import.
    final imports = List.of(pom.dependencyManagement
        .whereNot((el) => el.coordinate.contains('+'))
        .where((el) => el.scope == Scope.import.name));
    await Future.wait(imports.map((el) async {
      el.version =
          _resolveCoordVersion(el.coordinate, pom, parentPoms).toString();
      final impPoms = await _resolvePomAndParents(el.coordinate);
      final impDeps = impPoms.map((e) => e.dependencyManagement).flattened;
      pom.dependencyManagement
        ..remove(el)
        ..addAll(impDeps);
    }));

    return [pom, ...parentPoms];
  }

  final _alreadyResolved = <String>{};

  /// Resolve the [coordinate] artifact along with its dependencies.
  /// This is how the resolution works:
  /// 1. We fetch the POM of the artifact.
  /// 2. We resolve the artifact's parent if it has one.
  /// 3. If the version or group ID in the artifact's POM is null, we inherit
  ///     it from the parent. If the parent is also null, it's an error.
  /// 4. It is a common practice in Maven world to define dependencies in the
  ///     the artifact's or its parent's POM's dependencyManagement section,
  ///     and then only define their groupId and artifactId in the dependencies
  ///     section. We then need to resolve (in Maven's lingo, "interpolate")
  ///     these dependencies' versions from there.
  /// 4.1 It is also possible that the version is a variable. This variable could
  ///     be:
  ///     - defined in the artifact's or its parent's POM's properties section,
  ///     - a POM field reference (prefixed with 'project.', 'pom.' or '.'),
  ///     - or a special variable ('project.baseDir', 'project.baseUri', or
  ///       'maven.build.timestamp').
  ///     However, we don't handle special variables.
  /// 5. After the versions of the dependencies are resolved, we resolve them
  ///     and their dependencies (and so on) recursively.
  /// 6. Finally, we wrap this nicely in an [Artifact] and return.
  Future<List<Artifact>> resolveArtifact(
    String coordinate,
    Scope scope, {
    Version? version,
    List<String> exclude = const [],
  }) async {
    final metadata = ArtifactMetadata(coordinate);
    if (_alreadyResolved.contains('$coordinate@$scope') ||
        exclude.contains(coordinate)) {
      return [];
    }
    final poms = await _resolvePomAndParents(coordinate);
    final pom = poms.first;
    final parentPoms = poms.skip(1).toList();

    // Resolve the transitive parents.
    if (pom.parent != null) {
      pom.version ??= parentPoms.first.version;
      pom.groupId ??= parentPoms.first.groupId;
    }

    if (pom.version == null || pom.groupId == null) {
      throw Exception(
          'Artifact ${pom.coordinate} doesn\'t have a valid POM file (missing groupId and/or version)');
    }

    final deps = pom.dependencies
        // Older gradle versions allowed use of `+` in the version spec. Maven
        // doesn't support this, and Gradle also probably dropped support for it,
        // but there are still some projects, including one of the build lib's
        // transitive dependency, that use this. Ideally, we should handle this,
        // but for now, we just ignore these dependencies.
        // Related issue: https://github.com/gradle/gradle/issues/1232
        .whereNot((dep) {
          // TODO: Log this
          return dep.coordinate.contains('+');
        })
        .whereNot((dep) => dep.optional ?? false)
        .where((dep) {
          if (scope == Scope.compile || scope == Scope.runtime) {
            return dep.scope == Scope.compile.name ||
                dep.scope == Scope.runtime.name;
          }
          // We don't resolve dependencies of any other scopes, specifically the 
          // provided scope
          return false;
        });

    final resolvedDeps = await Future.wait(
      deps.map((dep) {
        final projectField = ['project.groupId', 'pom.groupId', '.groupId'];
        // If group id is in variable form (e.g. ${project.groupId}), then
        // interpolate it.
        if (projectField
            .contains(dep.groupId.substring(2, dep.groupId.length - 1))) {
          dep.groupId = pom.groupId!;
        }

        final resolvedVersion =
            _resolveCoordVersion(dep.coordinate, pom, parentPoms);
        final versionChanged =
            resolvedVersion.toString() != resolvedVersion.originalVersionSpec;

        dep.version = resolvedVersion.toString();
        return resolveArtifact(
          dep.coordinate, dep.scope.toScope(),
          // Only pass the version object if the original version spec is different
          // than the spec used to resolved the artifact. This can happen in only
          // one case and that is when the original spec was a version range.
          version: versionChanged ? resolvedVersion : null,
          exclude: exclude,
        );
      }),
    );

    if (version != null) {
      final newCoordinate =
          [...coordinate.split(':').take(2), version.toString()].join(':');
      coordinate = newCoordinate;
    }

    final result = resolvedDeps.flattened.toList();
    if (pom.packaging != 'pom') {
      result.insert(
        0,
        Artifact(
          coordinate: coordinate,
          scope: scope,
          artifactFile:
              p.join(_localMvnRepo, metadata.artifactPath(pom.packaging)),
          sourcesJar: p.join(_localMvnRepo, metadata.sourceJarPath()),
          dependencies: deps.map((el) => el.coordinate).toList(growable: true),
          packaging: pom.packaging,
        ),
      );
    }

    _alreadyResolved.add('$coordinate@$scope');
    return result;
  }

  Future<File> downloadArtifact(Artifact artifact) async {
    final metadata = ArtifactMetadata(artifact.coordinate);
    final file = await _fetchFile(metadata.artifactPath(artifact.packaging));
    if (file == null) {
      throw Exception(
          'Unable to find artifact file for ${artifact.coordinate} in any of the available Maven repositories.');
    }
    return file;
  }

  Future<File?> downloadSourcesJar(Artifact artifact) async {
    final metadata = ArtifactMetadata(artifact.coordinate);
    return await _fetchFile(metadata.sourceJarPath());
  }
}
