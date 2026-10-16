import 'package:rush/src/commands/build/library_plan.dart';
import 'package:rush/src/config/library_placement.dart';
import 'package:test/test.dart';

ResolvedLibrary _library(
  String coordinate, {
  LibraryScope scope = LibraryScope.compile,
  bool aar = false,
  List<String> dependencies = const [],
  String? package,
  bool consumerRules = false,
  bool inEveryApp = true,
  bool resources = false,
  Set<OriginalContent> originalContents = const {},
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
      inEveryApp: inEveryApp,
      hasResources: resources,
      originalContents: originalContents,
    );

LibraryPlan _plan({
  List<ResolvedLibrary> dependencies = const [],
  List<ResolvedLibrary> appInventor = const [],
  Map<String, LibraryPlacement> placements = const {},
}) =>
    planLibraries(
      dependencies: dependencies,
      appInventor: appInventor,
      placements: placements,
    );

List<String> _errors(LibraryPlan plan) => [
      for (final problem in plan.problems)
        if (problem.isError) problem.message,
    ];

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
    expect(_coordinates(plan.provided), ['g:provided:1']);
    expect(plan.libraryJars, {'g:provided:1.jar'});
  });

  test('makes every library private unless rush.yml shares it', () {
    final plan = _plan(dependencies: [
      _library('g:widget:1',
          aar: true, resources: true, dependencies: ['g:model:1']),
      _library('g:model:1', dependencies: ['g:util:1']),
      _library('g:util:1'),
      _library('g:codec:1', aar: true),
      _library('helper.jar'),
    ]);

    expect(plan.shared, isEmpty);
    expect(_coordinates(plan.privateAars), ['g:widget:1']);
    expect(plan.privateJars, {
      'g:model:1.jar',
      'g:util:1.jar',
      'g:codec:1.jar',
      'helper.jar.jar',
    });
  });

  test('compiles against provided libraries the extension does not ship', () {
    final plan = _plan(
      dependencies: [
        _library('com.google.code.gson:gson:2.13.2'),
        _library('g:host:1', scope: LibraryScope.provided),
      ],
      appInventor: [
        _library('rush-annotations', scope: LibraryScope.provided),
        _library('com.google.code.gson:gson:2.8.9',
            scope: LibraryScope.provided),
        _library('QRGenerator.jar', scope: LibraryScope.provided),
      ],
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
        _library('g:host:1',
            scope: LibraryScope.provided, dependencies: ['g:base:1']),
        _library('g:other:1', scope: LibraryScope.provided),
        _library('g:base:1', scope: LibraryScope.provided),
      ],
      placements: {'g:widget': LibraryPlacement.shared},
    );

    expect(plan.libraryJars.toList(), [
      'g:host:1.jar',
      'g:base:1.jar',
      'g:other:1.jar',
      'g:widget:1.jar',
      'g:model:1.jar',
    ]);
  });

  test('links against App Inventor libraries only when every app has them', () {
    final plan = _plan(
      dependencies: [_library('com.google.zxing:core:3.5.3')],
      appInventor: [
        _library('android.jar', scope: LibraryScope.provided),
        _library('QRGenerator.jar',
            scope: LibraryScope.provided, inEveryApp: false),
        _library('Barcode.jar',
            scope: LibraryScope.provided, inEveryApp: false),
      ],
    );

    expect(plan.libraryJars, {'android.jar.jar'});
    expect(plan.compileClasspath,
        containsAll(['QRGenerator.jar.jar', 'Barcode.jar.jar']));
  });

  test('compiles against everything but runtime-only dependencies', () {
    final plan = _plan(
      dependencies: [
        _library('g:api:1', dependencies: ['g:runtime:1']),
        _library('g:runtime:1', scope: LibraryScope.runtime),
        _library('g:impl:1', scope: LibraryScope.runtime),
        _library('g:host:1',
            scope: LibraryScope.provided, dependencies: ['g:base:1']),
        _library('g:base:1', scope: LibraryScope.provided),
      ],
      appInventor: [_library('android.jar', scope: LibraryScope.provided)],
    );

    expect(plan.compileClasspath.toList(), [
      'g:api:1.jar',
      'g:runtime:1.jar',
      'g:host:1.jar',
      'g:base:1.jar',
      'android.jar.jar',
    ]);
  });

  test('merges shipped AAR manifests and applies every AAR\'s rules', () {
    final plan = _plan(
      dependencies: [
        _library('g:widget:1', aar: true, consumerRules: true),
        _library('g:plain:1', aar: true),
        _library('g:host:1',
            scope: LibraryScope.provided, aar: true, consumerRules: true),
      ],
    );

    expect(plan.manifests,
        ['g:widget:1/AndroidManifest.xml', 'g:plain:1/AndroidManifest.xml']);
    expect(plan.consumerRules,
        {'g:widget:1/proguard.txt', 'g:host:1/proguard.txt'});
  });

  test('reports AARs that are the same library', () {
    final plan = _plan(
      dependencies: [
        _library('g:core:1', aar: true, package: 'androidx.core'),
        _library('core.aar', aar: true, package: 'androidx.core'),
        _library('g:other:1', aar: true, package: 'g.other'),
        _library('g:ui:1', aar: true, package: 'g.ui'),
        _library('ui.aar', aar: true, package: 'g.ui'),
      ],
      placements: {'g:core': LibraryPlacement.shared},
    );

    expect([
      for (final problem in plan.problems) problem.message
    ], [
      'g:core:1 and core.aar are the same library (androidx.core). App '
          'Inventor includes only one of them in the app, so remove the '
          'others from rush.yml.',
      'g:ui:1 and ui.aar are the same library (g.ui). App Inventor includes '
          'only one of them in the app, so remove the others from rush.yml.',
    ]);
  });

  test('places libraries where rush.yml says', () {
    final plan = _plan(
      dependencies: [
        _library('g:widget:1', aar: true, dependencies: ['g:util:1']),
        _library('g:util:1'),
        _library('g:json:1', dependencies: ['g:base:1']),
        _library('g:base:1'),
      ],
      placements: {
        'g:widget': LibraryPlacement.private,
        'g:json': LibraryPlacement.shared,
      },
    );

    expect(_coordinates(plan.shared), ['g:json:1', 'g:base:1']);
    expect(_coordinates(plan.private), ['g:widget:1', 'g:util:1']);
    expect(plan.problems, isEmpty);
  });

  test('merges the manifests of private AARs', () {
    final plan = _plan(
      dependencies: [_library('g:widget:1', aar: true)],
      placements: {'g:widget': LibraryPlacement.private},
    );

    expect(plan.manifests, ['g:widget:1/AndroidManifest.xml']);
  });

  test('refuses private libraries whose contents need them shared', () {
    final plan = _plan(
      dependencies: [
        _library('g:widget:1', aar: true, originalContents: {
          OriginalContent.assets,
          OriginalContent.nativeLibraries,
        }),
        _library('g:camera:1',
            aar: true, originalContents: {OriginalContent.nativeLibraries}),
      ],
      placements: {'g:widget': LibraryPlacement.private},
    );

    expect(_errors(plan), [
      'g:widget:1 can\'t be private: its assets keep their original paths '
          'and its native libraries find classes by their original names. '
          'Place it as shared in rush.yml: `libraries: {g:widget: shared}`.',
      'g:camera:1 can\'t be private: its native libraries find classes by '
          'their original names. Place it as shared in rush.yml: '
          '`libraries: {g:camera: shared}`.',
    ]);
  });

  test('ships private AARs with resources apart from private code', () {
    final plan = _plan(
      dependencies: [
        _library('g:widget:1', aar: true, resources: true),
        _library('g:codec:1', aar: true),
        _library('g:json:1'),
      ],
      placements: {
        'g:widget': LibraryPlacement.private,
        'g:codec': LibraryPlacement.private,
      },
    );

    expect(_errors(plan), isEmpty);
    expect(plan.privateAars.map((el) => el.coordinate), ['g:widget:1']);
    expect(plan.privateJars, {'g:codec:1.jar', 'g:json:1.jar'});
  });

  test('refuses private libraries a shared library uses', () {
    final plan = _plan(
      dependencies: [
        _library('g:widget:1', aar: true, dependencies: ['g:util:1']),
        _library('g:util:1'),
      ],
      placements: {
        'g:widget': LibraryPlacement.shared,
        'g:util': LibraryPlacement.private,
      },
    );

    expect(_errors(plan), [
      'g:util:1 can\'t be private: g:widget:1 ships unchanged and uses it by '
          'its original name. Remove it from `libraries` in rush.yml.',
    ]);
  });

  test('explains where each library goes', () {
    final plan = _plan(
      dependencies: [
        _library('g:widget:1', aar: true, dependencies: ['g:util:1']),
        _library('g:util:1'),
        _library('g:json:1'),
        _library('g:gson:1'),
        _library('g:host:1',
            scope: LibraryScope.provided, dependencies: ['g:base:1']),
        _library('g:base:1', scope: LibraryScope.provided),
      ],
      placements: {
        'g:widget': LibraryPlacement.shared,
        'g:gson': LibraryPlacement.shared,
        'g:host': LibraryPlacement.provided,
      },
    );

    expect(plan.placements, {
      'g:widget:1': 'shared: rush.yml',
      'g:util:1': 'shared: used by g:widget:1',
      'g:gson:1': 'shared: rush.yml',
      'g:json:1': 'private: default',
      'g:host:1': 'provided: rush.yml',
      'g:base:1': 'provided: only provided libraries need it',
    });
  });
}
