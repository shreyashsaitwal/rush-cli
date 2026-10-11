import 'package:collection/collection.dart';

import 'package:rush/src/config/config.dart';
import 'package:rush/src/resolver/artifact.dart';
import 'package:rush/src/services/lib_service.dart';

class BuildDependencies {
  BuildDependencies._({
    required this.privateJars,
    required this.sharedJars,
    required this.shippedAars,
    required this.referencedJars,
  });

  final Set<String> privateJars;

  final List<Artifact> sharedJars;

  final List<Artifact> shippedAars;

  final Set<String> referencedJars;

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
    );
  }
}
