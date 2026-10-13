import 'package:collection/collection.dart';
import 'package:get_it/get_it.dart';

import 'package:rush/src/config/config.dart';
import 'package:rush/src/resolver/artifact.dart';
import 'package:rush/src/services/file_service.dart';
import 'package:rush/src/services/lib_service.dart';

class BuildDependencies {
  BuildDependencies._({
    required this.privateJars,
    required this.sharedJars,
    required this.shippedAars,
    required this.referencedJars,
    required this.compileClasspath,
    required this.aarManifests,
    required this.aarProguardRules,
  });

  final Set<String> privateJars;

  final List<Artifact> sharedJars;

  final List<Artifact> shippedAars;

  final Set<String> referencedJars;

  final Set<String> compileClasspath;

  final List<String> aarManifests;

  final Set<String> aarProguardRules;

  static Future<BuildDependencies> load(
      LibService libService, Config config) async {
    final shipped = (await libService.extensionDependencies(config))
        .where((el) => el.scope == Scope.compile || el.scope == Scope.runtime)
        .toSet();
    final shippedLibraries = shipped
        .where((el) => el.isMavenArtifact)
        .map((el) => el.groupAndArtifactId)
        .toSet();
    final provided = (await libService.providedDependencies(config))
        .where((el) =>
            !el.isMavenArtifact ||
            !shippedLibraries.contains(el.groupAndArtifactId))
        .toList();
    final shippedAars = shipped.where((el) => el.packaging == 'aar').toList();
    final aarClasspath =
        shippedAars.map((el) => el.classpathJars(shipped)).flattened.toSet();
    final shippedJars = shipped.where((el) => el.packaging == 'jar');
    final sharedJars = shippedJars
        .where((el) => aarClasspath.contains(el.classesJar))
        .toList();
    final all = await libService.extensionDependencies(config,
        includeAi2ProvidedDeps: true, includeProjectProvidedDeps: true);

    return BuildDependencies._(
      privateJars: shippedJars
          .whereNot(sharedJars.contains)
          .map((el) => el.classesJar)
          .toSet(),
      sharedJars: sharedJars,
      shippedAars: shippedAars,
      referencedJars: {
        ...provided.map((el) => el.classpathJars(provided)).flattened,
        ...shippedAars.map((el) => el.classesJar),
        ...sharedJars.map((el) => el.classesJar),
      },
      compileClasspath: all
          .where(
              (el) => el.scope == Scope.compile || el.scope == Scope.provided)
          .map((el) => el.classpathJars(all))
          .flattened
          .toSet(),
      aarManifests: _existingAarFiles(shippedAars, 'AndroidManifest.xml'),
      aarProguardRules: _existingAarFiles(
              all.where((el) => el.packaging == 'aar'), 'proguard.txt')
          .toSet(),
    );
  }

  static List<String> _existingAarFiles(
      Iterable<Artifact> aars, String fileName) {
    final fs = GetIt.I<FileService>();
    return aars
        .map((el) => fs.resourceFromExtractedAar(el.artifactFile, fileName))
        .where((el) => el.existsSync())
        .map((el) => el.path)
        .toList();
  }
}
