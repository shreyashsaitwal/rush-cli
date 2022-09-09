import 'dart:io';

import 'package:collection/collection.dart';
import 'package:get_it/get_it.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:rush_cli/services/logger.dart';

import './artifact.dart';
import './pom.dart';
import '../utils/file_extension.dart';

class _ArtifactMetadata {
  late final String groupId;
  late final String artifactId;
  late final String version;

  _ArtifactMetadata(String coordinate) {
    final parts = coordinate.split(':');
    if (parts.length != 3) {
      throw Exception(
          'Invalid artifact coordinate format: $coordinate\nExpected format: <groupId>:<artifactId>:<version>');
    }
    groupId = coordinate.split(':')[0];
    artifactId = coordinate.split(':')[1];
    version = coordinate.split(':')[2];
  }

  String _basePath() =>
      p.joinAll([...groupId.split('.'), artifactId, version]).replaceAll(
          '\\', '/');

  String pomPath() =>
      p.join(_basePath(), '$artifactId-$version.pom').replaceAll('\\', '/');

  String artifactPath(String packaging) => p
      .join(_basePath(), '$artifactId-$version.$packaging')
      .replaceAll('\\', '/');

  String sourceJarPath() => p
      .join(_basePath(), '$artifactId-$version-sources.jar')
      .replaceAll('\\', '/');
}

class ArtifactResolver {
  static const defaultRepos = <String>{
    'https://dl.google.com/dl/android/maven2',
    'https://repo.maven.apache.org/maven2',
    'https://maven-central.storage-download.googleapis.com/repos/central/data',
    'https://jcenter.bintray.com',
  };
  final _lgr = GetIt.I<Logger>();

  late final String cacheDir;

  ArtifactResolver({String? cacheDir}) {
    if (cacheDir != null) {
      this.cacheDir = cacheDir;
    } else if (Platform.isWindows) {
      this.cacheDir =
          p.join(Platform.environment['UserProfile']!, '.m2').asDir(true).path;
    } else {
      this.cacheDir =
          p.join(Platform.environment['HOME']!, '.m2').asDir(true).path;
    }
  }

  Future<File> _fetchFile(String relativePath) async {
    final file = p.join(cacheDir, relativePath).asFile();
    if (file.existsSync()) return file;

    _lgr.dbg('${file.path} does not exist, downloading...');
    await file.create(recursive: true);

    for (final repo in defaultRepos) {
      final uri = Uri.parse('$repo/$relativePath');
      try {
        final response = await http.get(uri);
        // TODO: Handle other response codes when implementing logging.
        if (response.statusCode == 200) {
          await file.writeAsBytes(response.bodyBytes, flush: true);
          return file;
        }
        continue;
      } catch (e) {
        _lgr.dbg(e.toString());
      }
    }

    await file.delete();
    throw Exception('Unable to fetch $relativePath');
  }

  /// For details on how this (roughly) works:
  /// https://maven.apache.org/guides/introduction/introduction-to-the-pom.html#project-interpolation-and-variables
  Version _resolveDepVersion(Dependency dependency, Pom pom, Pom? parentPom) {
    var version = dependency.version;
    final exception = Exception(
        'Couldn\'t resolve dependency (${dependency.coordinate}) of artifact ${pom.coordinate}');

    // If the version is defined in a range, pick the upper endpoint if it is
    // upper bounded otherwise pick the lower endpoint for now.
    if (version != null && Version.rangeRegex.hasMatch(version)) {
      final range = Version.from(version).range;
      if (!range!.upperBounded) {
        return Version.from(range.lower!.versionSpec, origialSpec: version);
      }
      return Version.from(range.upper!.versionSpec, origialSpec: version);
    }

    // If the version is null, then it should be stored in the [pom] or [parentPom]
    // as a implicit value or as variable.
    version ??= pom.dependencyManagement
        // First, check for this dependency in the same POM's dependencyManagement section.
        .firstWhere(
      (el) =>
          el.artifactId == dependency.artifactId &&
          el.groupId == dependency.groupId,
      // If not found, check in the parent POM's dependencyManagement section.
      orElse: () {
        if (parentPom == null) {
          throw exception;
        }
        return parentPom.dependencyManagement.firstWhere(
          (el) =>
              el.artifactId == dependency.artifactId &&
              el.groupId == dependency.groupId,
          // If still not found, throw an exception.
          orElse: () => throw exception,
        );
      },
    ).version!;

    // The below implementation of varible interpolation isn't (probably?) the
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
      // When the varible is a POM field. Note: This can only ever be a single
      // value field.
      if (variable.startsWith('project.') ||
          variable.startsWith('pom.') ||
          variable.startsWith('.')) {
        final split = variable.split('.');
        if (split.length > 2) {
          throw exception;
        }
        switch (split.last) {
          // To me, this seems the only valid case. Why would someone set the
          // version to, say, something like ${project.artifactId}?
          case 'version':
            return Version.from(pom.version!);
          default:
            throw exception;
        }
      }

      // When the variable is a POM property.
      final properties = {
        ...pom.properties,
        ...?parentPom?.properties,
      };

      if (properties.containsKey(variable)) {
        return Version.from(properties[variable]!.toString());
      } else {
        throw exception;
      }
    }

    // Version is likely a normal version literal.
    return Version.from(dependency.version!);
  }

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
    Scope scope, [
    Version? version,
  ]) async {
    final metadata = _ArtifactMetadata(coordinate);
    final pomFile = await _fetchFile(metadata.pomPath());
    _lgr.dbg('Fetched POM: ${pomFile.path}');

    final pom = Pom.fromXml(pomFile.readAsStringSync());
    final Pom? parentPom;

    if (pom.version == null || pom.groupId == null) {
      if (pom.parent == null) {
        throw Exception(
            'Artifact ${pom.coordinate} doesn\'t have a valid POM file (missing groupId and/or version)');
      } else {
      _lgr.dbg(
          '$coordinate POM has no version or group ID; fetching parent POM ${pom.parent!.coordinate}');
        // TODO: Investigate why I chose to resolve the parent here. I remember
        // I did it for some reason, but don't remember what it was. :(
        // final parentArtifact =
        //     await resolveArtifact(pom.parent!.coordinate, scope);
        // final parentMetadata =
        //     _ArtifactMetadata(parentArtifact.first.coordinate);

        final parentMetadata = _ArtifactMetadata(pom.parent!.coordinate);
        parentPom = Pom.fromXml(
            (await _fetchFile(parentMetadata.pomPath())).readAsStringSync());

        pom.version ??= parentMetadata.version;
        pom.groupId ??= parentMetadata.groupId;
        _lgr.dbg('pom.version: ${pom.version}; pom.groupId: ${pom.groupId}');
      }
    } else {
      parentPom = null;
    }

    final deps =
        pom.dependencies.whereNot((dep) => dep.optional ?? false).where((dep) {
      if (scope == Scope.compile) {
        return dep.scope == Scope.compile.name;
      } else if (scope == Scope.runtime) {
        return dep.scope == Scope.runtime.name ||
            dep.scope == Scope.compile.name;
      }
      return false;
    });
    _lgr.dbg('$coordinate: Total ${pom.dependencies.length} deps defined; ${deps.length} selected');

    final result = <Artifact>[];
    for (final dep in deps) {
      final resolvedVersion = _resolveDepVersion(dep, pom, parentPom);
      final versionChanged =
          resolvedVersion.versionSpec != resolvedVersion.originalSpec;
      if (versionChanged) {
        _lgr.dbg(
            'Changed version: ${dep.version} -> $resolvedVersion');
      }

      dep.version = resolvedVersion.versionSpec;
      result.addAll(await resolveArtifact(
          dep.coordinate,
          dep.scope?.toScope() ?? Scope.compile,
          // Only pass the version object if the original version spec is different
          // than the spec used to resolved the artifact. This can happen in only
          // one case and that is when the original spec was a version range.
          versionChanged ? resolvedVersion : null));
    }

    if (version != null) {
      final newCoordinate = [...coordinate.split(':').take(2), version.originalSpec].join(':');
      _lgr.dbg('Changed coord: $coordinate -> $newCoordinate');
      coordinate = newCoordinate;
    }

    _lgr.info('Resolved $coordinate and its dependencies');
    return result
      ..insert(
        0,
        Artifact(
          coordinate: coordinate,
          scope: scope,
          artifactFile: p.join(cacheDir, metadata.artifactPath(pom.packaging)),
          sourceJar: p.join(cacheDir, metadata.sourceJarPath()),
          dependencies: deps.map((el) => el.coordinate).toList(growable: true),
          isAar: pom.packaging == 'aar',
        ),
      );
  }

  Future<void> downloadArtifact(Artifact artifact) async {
    final metadata = _ArtifactMetadata(artifact.coordinate);
    await _fetchFile(metadata.artifactPath(artifact.isAar ? 'aar' : 'jar'));
  }

  Future<void> downloadSourceJar(Artifact artifact) async {
    final metadata = _ArtifactMetadata(artifact.coordinate);
    try {
      await _fetchFile(metadata.sourceJarPath());
    } catch (_) {
      _lgr.warn('Could not resolve source JAR for ${artifact.coordinate}');
    }
  }
}
