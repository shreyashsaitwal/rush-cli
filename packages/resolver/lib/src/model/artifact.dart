import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:path/path.dart' as p;

part 'artifact.freezed.dart';

@freezed
class Artifact with _$Artifact {
  const factory Artifact({
    required String groupId,
    required String artifactId,
    required String version,
    required String cacheDir,
  }) = _Artifact;

  const Artifact._();

  String get spec => '$groupId:$artifactId:$version';

  PomFile get pom => PomFile._(this, cacheDir);
}

class FileSpec {
  final Artifact artifact;
  final String cacheDir;
  final String path;
  final String localFile;

  FileSpec(this.artifact, this.cacheDir, this.path, this.localFile);
}

class PomFile implements FileSpec {
  const PomFile._(this.artifact, this.cacheDir);

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
}
