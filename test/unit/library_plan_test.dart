import 'package:rush/src/commands/build/library_plan.dart';
import 'package:test/test.dart';

ResolvedLibrary _library(
  String coordinate, {
  LibraryScope scope = LibraryScope.compile,
  bool aar = false,
  List<String> dependencies = const [],
  String? package,
  bool consumerRules = false,
}) =>
    ResolvedLibrary(
      coordinate: coordinate,
      scope: scope,
      isAar: aar,
      file: '$coordinate.${aar ? 'aar' : 'jar'}',
      classesJar: '$coordinate.jar',
      dependencies: dependencies,
      manifest: aar ? '$coordinate/AndroidManifest.xml' : null,
      consumerRules: consumerRules ? '$coordinate/proguard.txt' : null,
      package: package,
    );

LibraryPlan _plan({
  List<ResolvedLibrary> dependencies = const [],
  List<ResolvedLibrary> appInventor = const [],
  List<ResolvedLibrary> provided = const [],
  List<ResolvedLibrary> providedWithDependencies = const [],
}) =>
    planLibraries(
      dependencies: dependencies,
      appInventor: appInventor,
      provided: provided,
      providedWithDependencies: providedWithDependencies,
    );

List<String> _coordinates(Iterable<ResolvedLibrary> libraries) =>
    [for (final library in libraries) library.coordinate];

void main() {
  test('ships compile and runtime dependencies but not provided ones', () {
    final plan = _plan(dependencies: [
      _library('g:compile:1'),
      _library('g:runtime:1', scope: LibraryScope.runtime),
      _library('g:provided:1', scope: LibraryScope.provided),
    ]);

    expect(_coordinates(plan.private), ['g:compile:1', 'g:runtime:1']);
    expect(plan.shared, isEmpty);
  });

  test('shares AARs and the jars they need, and relocates the other jars', () {
    final plan = _plan(dependencies: [
      _library('g:widget:1', aar: true, dependencies: ['g:model:1']),
      _library('g:model:1', dependencies: ['g:util:1']),
      _library('g:util:1'),
      _library('g:json:1'),
      _library('helper.jar'),
    ]);

    expect(_coordinates(plan.sharedAars), ['g:widget:1']);
    expect(_coordinates(plan.sharedJars), ['g:model:1', 'g:util:1']);
    expect(_coordinates(plan.private), ['g:json:1', 'helper.jar']);
    expect(plan.privateJars, {'g:json:1.jar', 'helper.jar.jar'});
  });

  test('compiles against provided libraries the extension does not ship', () {
    final plan = _plan(
      dependencies: [_library('com.google.code.gson:gson:2.13.2')],
      appInventor: [
        _library('rush-annotations', scope: LibraryScope.provided),
        _library('com.google.code.gson:gson:2.8.9',
            scope: LibraryScope.provided),
        _library('QRGenerator.jar', scope: LibraryScope.provided),
      ],
      provided: [_library('g:host:1', scope: LibraryScope.provided)],
    );

    expect(_coordinates(plan.provided),
        ['rush-annotations', 'QRGenerator.jar', 'g:host:1']);
  });

  test('resolves library jars from provided libraries, then shared ones', () {
    final plan = _plan(
      dependencies: [
        _library('g:widget:1', aar: true, dependencies: ['g:model:1']),
        _library('g:model:1'),
        _library('g:json:1'),
      ],
      provided: [
        _library('g:host:1',
            scope: LibraryScope.provided, dependencies: ['g:base:1']),
        _library('g:other:1', scope: LibraryScope.provided),
        _library('g:base:1', scope: LibraryScope.provided),
      ],
    );

    expect(plan.libraryJars.toList(), [
      'g:host:1.jar',
      'g:base:1.jar',
      'g:other:1.jar',
      'g:widget:1.jar',
      'g:model:1.jar',
    ]);
  });

  test('compiles against everything but runtime-only dependencies', () {
    final plan = _plan(
      dependencies: [
        _library('g:api:1', dependencies: ['g:runtime:1']),
        _library('g:runtime:1', scope: LibraryScope.runtime),
        _library('g:impl:1', scope: LibraryScope.runtime),
      ],
      appInventor: [_library('android.jar', scope: LibraryScope.provided)],
      provided: [_library('g:host:1', scope: LibraryScope.provided)],
      providedWithDependencies: [
        _library('g:host:1', dependencies: ['g:base:1']),
        _library('g:base:1'),
      ],
    );

    expect(plan.compileClasspath.toList(), [
      'g:api:1.jar',
      'g:runtime:1.jar',
      'android.jar.jar',
      'g:host:1.jar',
      'g:base:1.jar',
    ]);
  });

  test('merges shared AAR manifests and applies every AAR\'s rules', () {
    final plan = _plan(
      dependencies: [
        _library('g:widget:1', aar: true, consumerRules: true),
        _library('g:plain:1', aar: true),
      ],
      providedWithDependencies: [
        _library('g:host:1', aar: true, consumerRules: true),
      ],
    );

    expect(plan.manifests,
        ['g:widget:1/AndroidManifest.xml', 'g:plain:1/AndroidManifest.xml']);
    expect(plan.consumerRules,
        {'g:widget:1/proguard.txt', 'g:host:1/proguard.txt'});
  });

  test('reports shared AARs that are the same library', () {
    final plan = _plan(dependencies: [
      _library('g:core:1', aar: true, package: 'androidx.core'),
      _library('core.aar', aar: true, package: 'androidx.core'),
      _library('g:other:1', aar: true, package: 'g.other'),
    ]);

    expect([
      for (final problem in plan.problems) problem.message
    ], [
      'g:core:1 and core.aar are the same library (androidx.core). App '
          'Inventor includes only one of them in the app, so remove the '
          'others from rush.yml.',
    ]);
  });
}
