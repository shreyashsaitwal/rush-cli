import 'file_spec.dart';
import 'maven/pom_model.dart';

class Artifact {
  final String groupId;
  final String artifactId;
  final String version;
  final String cacheDir;

  const Artifact({
    required this.groupId,
    required this.artifactId,
    required this.version,
    required this.cacheDir,
  });

  String get coordinate => '$groupId:$artifactId:$version';

  PomFileSpec get pomSpec => PomFileSpec(this, cacheDir);
}

class ResolvedArtifact extends Artifact {
  final PomModel pom;
  final DependencyScope scope;

  ResolvedArtifact(
      {required this.pom, required this.scope, required String cacheDir})
      : super(
            groupId: pom.groupId,
            artifactId: pom.artifactId,
            version: pom.version,
            cacheDir: cacheDir);

  String get suffix => () {
        if (pom.packaging == 'bom') {
          return 'pom';
        } else if (pom.packaging == 'bundle') {
          return 'jar';
        } else {
          return pom.packaging;
        }
      }();

  ArtifactFileSpec get main => ArtifactFileSpec(this, cacheDir);

  SourcesFileSpec get sources => SourcesFileSpec(this, cacheDir);
}
