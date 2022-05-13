import 'package:path/path.dart' as p;

import 'artifact.dart';

abstract class FileSpec {
  final Artifact artifact;
  final String cacheDir;
  final String path;
  final String localFile;

  FileSpec(this.artifact, this.cacheDir, this.path, this.localFile);
}

class PomFileSpec implements FileSpec {
  const PomFileSpec(this.artifact, this.cacheDir);

  @override
  final Artifact artifact;

  @override
  final String cacheDir;

  @override
  String get localFile => p.join(cacheDir, path);

  @override
  String get path => p.joinAll(
        [
          ...artifact.groupId.split('.'),
          artifact.artifactId,
          artifact.version,
          '${artifact.artifactId}-${artifact.version}.pom'
        ],
      );

  @override
  String toString() {
    return '''
PomFileSpec(
  artifact: $artifact, 
  cacheDir: $cacheDir, 
  path: $path, 
  localFile: $localFile,
)''';
  }
}

class ArtifactFileSpec implements FileSpec {
  const ArtifactFileSpec(this.artifact, this.cacheDir);

  @override
  final ResolvedArtifact artifact;

  @override
  final String cacheDir;

  @override
  String get localFile => p.join(cacheDir, path);

  @override
  String get path => p.joinAll(
        [
          ...artifact.groupId.split('.'),
          artifact.artifactId,
          artifact.version,
          '${artifact.artifactId}-${artifact.version}.${artifact.packaging}',
        ],
      );

  @override
  String toString() {
    return '''
ArtifactFileSpec(
  artifact: $artifact, 
  cacheDir: $cacheDir, 
  path: $path, 
  localFile: $localFile
)''';
  }
}

class SourcesFileSpec implements FileSpec {
  const SourcesFileSpec(this.artifact, this.cacheDir);

  @override
  final ResolvedArtifact artifact;

  @override
  final String cacheDir;

  @override
  String get localFile => p.join(cacheDir, path);

  @override
  String get path => p.joinAll(
        [
          ...artifact.groupId.split('.'),
          artifact.artifactId,
          artifact.version,
          '${artifact.artifactId}-${artifact.version}-sources.jar',
        ],
      );

  @override
  String toString() {
    return '''
SourcesFileSpec(
  artifact: $artifact, 
  cacheDir: $cacheDir, 
  path: $path, 
  localFile: $localFile
)''';
  }
}
