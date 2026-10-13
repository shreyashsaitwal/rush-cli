import 'package:collection/collection.dart';

import 'package:rush/src/commands/build/libraries.dart';

enum LibraryScope { compile, runtime, provided }

class ResolvedLibrary {
  const ResolvedLibrary({
    required this.coordinate,
    required this.scope,
    required this.isAar,
    required this.file,
    required this.classesJar,
    this.dependencies = const [],
    this.manifest,
    this.consumerRules,
    this.package,
  });

  final String coordinate;
  final LibraryScope scope;
  final bool isAar;
  final String file;
  final String classesJar;
  final List<String> dependencies;
  final String? manifest;
  final String? consumerRules;
  final String? package;

  String get groupId => coordinate.split(':')[0];

  String get artifactId => coordinate.split(':')[1];

  bool get isMavenArtifact => coordinate.split(':').length >= 3;

  String get groupAndArtifactId => '$groupId:$artifactId';

  @override
  String toString() => coordinate;
}

class Problem {
  const Problem(this.message);

  final String message;
}

class LibraryPlan {
  const LibraryPlan({
    required this.shared,
    required this.private,
    required this.provided,
    required this.problems,
    required this.compileClasspath,
    required this.libraryJars,
    required this.manifests,
    required this.consumerRules,
  });

  final List<ResolvedLibrary> shared;
  final List<ResolvedLibrary> private;
  final List<ResolvedLibrary> provided;
  final List<Problem> problems;
  final Set<String> compileClasspath;
  final Set<String> libraryJars;
  final List<String> manifests;
  final Set<String> consumerRules;

  Iterable<ResolvedLibrary> get sharedAars => shared.where((el) => el.isAar);

  Iterable<ResolvedLibrary> get sharedJars => shared.whereNot((el) => el.isAar);

  Set<String> get privateJars => {for (final jar in private) jar.classesJar};
}

LibraryPlan planLibraries({
  required List<ResolvedLibrary> dependencies,
  required List<ResolvedLibrary> appInventor,
  required List<ResolvedLibrary> provided,
  required List<ResolvedLibrary> providedWithDependencies,
}) {
  final shipped = _shipped(dependencies);
  final shared = _shared(shipped);
  final compileOnly = _compileOnly([...appInventor, ...provided], shipped);
  final sharedAars = shared.where((el) => el.isAar);
  final everything = [
    ...dependencies,
    ...appInventor,
    ...provided,
    ...providedWithDependencies,
  ];
  return LibraryPlan(
    shared: shared,
    private: shipped.whereNot(shared.contains).toList(),
    provided: compileOnly,
    problems: _duplicateAars(sharedAars),
    compileClasspath: everything
        .where((el) => el.scope != LibraryScope.runtime)
        .expand((el) => _classpath(el, everything))
        .toSet(),
    libraryJars: {
      ...compileOnly.expand((el) => _classpath(el, compileOnly)),
      ...sharedAars.map((el) => el.classesJar),
      ...shared.whereNot((el) => el.isAar).map((el) => el.classesJar),
    },
    manifests: sharedAars.map((el) => el.manifest).nonNulls.toList(),
    consumerRules: everything.map((el) => el.consumerRules).nonNulls.toSet(),
  );
}

List<ResolvedLibrary> _shipped(List<ResolvedLibrary> dependencies) =>
    dependencies.where((el) => el.scope != LibraryScope.provided).toList();

List<ResolvedLibrary> _shared(List<ResolvedLibrary> shipped) {
  final aarClasspath = shipped
      .where((el) => el.isAar)
      .expand((el) => _classpath(el, shipped))
      .toSet();
  return shipped
      .where((el) => el.isAar || aarClasspath.contains(el.classesJar))
      .toList();
}

List<ResolvedLibrary> _compileOnly(
    List<ResolvedLibrary> provided, List<ResolvedLibrary> shipped) {
  final shippedLibraries = shipped
      .where((el) => el.isMavenArtifact)
      .map((el) => el.groupAndArtifactId)
      .toSet();
  return provided
      .where((el) =>
          !el.isMavenArtifact ||
          !shippedLibraries.contains(el.groupAndArtifactId))
      .toList();
}

List<Problem> _duplicateAars(Iterable<ResolvedLibrary> aars) => [
      for (final MapEntry(key: package, value: copies) in duplicateLibraries({
        for (final aar in aars)
          if (aar.package case final package?) aar: package,
      }).entries)
        Problem('${copies.join(' and ')} are the same library ($package). '
            'App Inventor includes only one of them in the app, so remove '
            'the others from rush.yml.'),
    ];

Set<String> _classpath(ResolvedLibrary library, List<ResolvedLibrary> index) =>
    {
      library.classesJar,
      ...library.dependencies
          .map((dependency) =>
              index.firstWhereOrNull((el) => el.coordinate == dependency))
          .nonNulls
          .expand((el) => _classpath(el, index)),
    };
