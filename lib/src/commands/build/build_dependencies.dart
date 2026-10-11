import 'package:collection/collection.dart';

import 'package:rush/src/config/config.dart';
import 'package:rush/src/resolver/artifact.dart';
import 'package:rush/src/services/lib_service.dart';

class BuildDependencies {
  BuildDependencies._({
    required this.shippedJars,
    required this.shippedAars,
    required this.referencedJars,
  });

  final Set<String> shippedJars;

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

    return BuildDependencies._(
      shippedJars: shipped
          .where((el) => el.packaging == 'jar')
          .map((el) => el.classesJar)
          .toSet(),
      shippedAars: shippedAars,
      referencedJars: {
        ...provided.map((el) => el.classpathJars(provided)).flattened,
        ...shippedAars.map((el) => el.classesJar),
      },
    );
  }
}
