import 'package:collection/collection.dart';
import 'package:path/path.dart' as p;

import 'package:rush/src/commands/build/libraries.dart';
import 'package:rush/src/config/library_placement.dart';

enum LibraryScope { compile, runtime, provided }

enum OriginalContent {
  assets('its assets keep their original paths'),
  nativeLibraries('its native libraries find classes by their original names');

  const OriginalContent(this.description);

  final String description;
}

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
    this.inEveryApp = true,
    this.hasResources = false,
    this.originalContents = const {},
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
  final bool inEveryApp;
  final bool hasResources;
  final Set<OriginalContent> originalContents;

  String get key => libraryKey(coordinate);

  String get groupId => coordinate.split(':')[0];

  String get artifactId => coordinate.split(':')[1];

  bool get isMavenArtifact => coordinate.split(':').length >= 3;

  String get groupAndArtifactId => '$groupId:$artifactId';

  String get aarFileName => isMavenArtifact
      ? '${coordinate.replaceAll(':', '-')}.aar'
      : p.basename(file);

  @override
  String toString() => coordinate;
}

class Problem {
  const Problem.warning(this.message) : isError = false;

  const Problem.error(this.message) : isError = true;

  final String message;
  final bool isError;
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
    required this.placements,
  });

  final List<ResolvedLibrary> shared;
  final List<ResolvedLibrary> private;
  final List<ResolvedLibrary> provided;
  final List<Problem> problems;
  final Set<String> compileClasspath;
  final Set<String> libraryJars;
  final List<String> manifests;
  final Set<String> consumerRules;
  final Map<String, String> placements;

  Iterable<ResolvedLibrary> get sharedAars => shared.where((el) => el.isAar);

  Iterable<ResolvedLibrary> get sharedJars => shared.whereNot((el) => el.isAar);

  Set<String> get privateJars =>
      {for (final library in private.whereNot(_shipsAar)) library.classesJar};

  Iterable<ResolvedLibrary> get privateAars => private.where(_shipsAar);

  static bool _shipsAar(ResolvedLibrary library) =>
      library.isAar && library.hasResources;
}

LibraryPlan planLibraries({
  required List<ResolvedLibrary> dependencies,
  required List<ResolvedLibrary> appInventor,
  required Map<String, LibraryPlacement> placements,
}) {
  final shipped = _shipped(dependencies);
  final shared = _shared(shipped, placements);
  final private = shipped.whereNot(shared.contains).toList();
  final compileOnly = _compileOnly([
    ...appInventor,
    ...dependencies.where((el) => el.scope == LibraryScope.provided),
  ], shipped);
  final linkedAgainst = _inEveryApp(compileOnly);
  final sharedAars = shared.where((el) => el.isAar);
  final everything = [...dependencies, ...appInventor];
  return LibraryPlan(
    shared: shared,
    private: private,
    provided: compileOnly,
    problems: [
      ..._misplacedPrivateLibraries(shared, private, placements),
      ..._duplicateAars(sharedAars),
    ],
    compileClasspath: everything
        .where((el) => el.scope != LibraryScope.runtime)
        .expand((el) => _classpath(el, everything))
        .toSet(),
    libraryJars: {
      ...linkedAgainst.expand((el) => _classpath(el, linkedAgainst)),
      ...sharedAars.map((el) => el.classesJar),
      ...shared.whereNot((el) => el.isAar).map((el) => el.classesJar),
    },
    manifests: shipped
        .where((el) => el.isAar)
        .map((el) => el.manifest)
        .nonNulls
        .toList(),
    consumerRules: everything.map((el) => el.consumerRules).nonNulls.toSet(),
    placements: {
      for (final library in shared)
        library.coordinate:
            'shared: ${_whyShared(library, shared, placements)}',
      for (final library in private)
        library.coordinate:
            'private: ${_placedInRushYml(library, placements) ? 'rush.yml' : 'jar'}',
      for (final library
          in dependencies.where((el) => el.scope == LibraryScope.provided))
        library.coordinate: 'provided: '
            '${_placedInRushYml(library, placements) ? 'rush.yml' : 'only provided libraries need it'}',
    },
  );
}

List<ResolvedLibrary> _shipped(List<ResolvedLibrary> dependencies) =>
    dependencies.where((el) => el.scope != LibraryScope.provided).toList();

List<ResolvedLibrary> _shared(
    List<ResolvedLibrary> shipped, Map<String, LibraryPlacement> placements) {
  final sharedClasspath = shipped
      .where((el) => switch (placements[el.key]) {
            LibraryPlacement.shared => true,
            LibraryPlacement.private => false,
            _ => el.isAar,
          })
      .expand((el) => _classpath(el, shipped))
      .toSet();
  return shipped
      .where((el) => sharedClasspath.contains(el.classesJar))
      .toList();
}

String _whyShared(ResolvedLibrary library, List<ResolvedLibrary> shared,
        Map<String, LibraryPlacement> placements) =>
    _placedInRushYml(library, placements)
        ? 'rush.yml'
        : library.isAar
            ? 'AAR'
            : 'used by ${shared.firstWhere((el) => el.dependencies.contains(library.coordinate))}';

bool _placedInRushYml(
        ResolvedLibrary library, Map<String, LibraryPlacement> placements) =>
    placements.containsKey(library.key);

List<Problem> _misplacedPrivateLibraries(
        List<ResolvedLibrary> shared,
        List<ResolvedLibrary> private,
        Map<String, LibraryPlacement> placements) =>
    [
      for (final library in shared)
        if (placements[library.key] == LibraryPlacement.private)
          if (shared.firstWhereOrNull(
                  (el) => el.dependencies.contains(library.coordinate))
              case final user?)
            Problem.error('$library can\'t be private: $user ships unchanged '
                'and uses it by its original name. Remove it from '
                '`libraries` in rush.yml.'),
      for (final library in private)
        if (library.originalContents.isNotEmpty)
          Problem.error('$library can\'t be private: '
              '${_listed(library.originalContents.map((el) => el.description).toList())}. '
              'Place it as shared or remove it from `libraries` in rush.yml.'),
    ];

String _listed(List<String> items) => items.length == 1
    ? items.single
    : '${items.take(items.length - 1).join(', ')} and ${items.last}';

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

List<ResolvedLibrary> _inEveryApp(List<ResolvedLibrary> libraries) =>
    libraries.where((el) => el.inEveryApp).toList();

List<Problem> _duplicateAars(Iterable<ResolvedLibrary> aars) => [
      for (final MapEntry(key: package, value: copies) in duplicateLibraries({
        for (final aar in aars)
          if (aar.package case final package?) aar: package,
      }).entries)
        Problem.warning(
            '${copies.join(' and ')} are the same library ($package). '
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
