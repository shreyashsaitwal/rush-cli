import 'dart:io';

import 'package:maven_resolver/maven_resolver.dart';
import 'package:test/test.dart';

void main() {
  group('PomInterpolator', () {
    late PomInterpolator interpolator;
    late PomParser parser;

    setUp(() {
      interpolator = const PomInterpolator();
      parser = const PomParser();
    });

    group('interpolate - basic properties', () {
      test('resolves simple property reference', () {
        final pom = Pom(
          artifactId: 'test',
          properties: {'my.version': '1.0.0'},
          dependencies: [
            Dependency(
              groupId: 'org.example',
              artifactId: 'lib',
              version: r'${my.version}',
            ),
          ],
        );

        final effective = interpolator.interpolate(pom);

        expect(effective.dependencies[0].version, '1.0.0');
      });

      test('resolves nested property references', () {
        final pom = Pom(
          artifactId: 'test',
          properties: {
            'base.version': '1.0.0',
            'full.version': r'${base.version}-SNAPSHOT',
          },
          dependencies: [
            Dependency(
              groupId: 'org.example',
              artifactId: 'lib',
              version: r'${full.version}',
            ),
          ],
        );

        final effective = interpolator.interpolate(pom);

        expect(effective.dependencies[0].version, '1.0.0-SNAPSHOT');
      });

      test('resolves multiple properties in one value', () {
        final pom = Pom(
          artifactId: 'test',
          properties: {
            'group': 'org.example',
            'artifact': 'my-lib',
          },
          dependencies: [
            Dependency(
              groupId: r'${group}',
              artifactId: r'${artifact}',
              version: '1.0.0',
            ),
          ],
        );

        final effective = interpolator.interpolate(pom);

        expect(effective.dependencies[0].groupId, 'org.example');
        expect(effective.dependencies[0].artifactId, 'my-lib');
      });

      test('leaves unresolved properties unchanged', () {
        final pom = Pom(
          artifactId: 'test',
          dependencies: [
            Dependency(
              groupId: 'org.example',
              artifactId: 'lib',
              version: r'${unknown.property}',
            ),
          ],
        );

        final effective = interpolator.interpolate(pom);

        expect(effective.dependencies[0].version, r'${unknown.property}');
      });

      test('handles circular references without infinite loop', () {
        final pom = Pom(
          artifactId: 'test',
          properties: {
            'a': r'${b}',
            'b': r'${a}',
          },
          dependencies: [
            Dependency(
              groupId: 'org.example',
              artifactId: 'lib',
              version: r'${a}',
            ),
          ],
        );

        // Should not hang, should leave partially resolved
        final effective = interpolator.interpolate(pom);
        expect(effective.dependencies[0].version, isNotNull);
      });
    });

    group('interpolate - project properties', () {
      test('resolves project.version', () {
        final pom = Pom(
          groupId: 'org.example',
          artifactId: 'parent',
          version: '2.0.0',
          dependencies: [
            Dependency(
              groupId: 'org.example',
              artifactId: 'child',
              version: r'${project.version}',
            ),
          ],
        );

        final effective = interpolator.interpolate(pom);

        expect(effective.dependencies[0].version, '2.0.0');
      });

      test('resolves project.groupId', () {
        final pom = Pom(
          groupId: 'org.example',
          artifactId: 'test',
          version: '1.0.0',
          dependencies: [
            Dependency(
              groupId: r'${project.groupId}',
              artifactId: 'sibling',
              version: '1.0.0',
            ),
          ],
        );

        final effective = interpolator.interpolate(pom);

        expect(effective.dependencies[0].groupId, 'org.example');
      });

      test('resolves project.artifactId', () {
        final pom = Pom(
          groupId: 'org.example',
          artifactId: 'my-project',
          version: '1.0.0',
          name: r'${project.artifactId}',
        );

        final effective = interpolator.interpolate(pom);

        expect(effective.pom.name, 'my-project');
      });

      test('resolves project.parent.version', () {
        final pom = Pom(
          artifactId: 'child',
          parent: ParentRef(
            groupId: 'org.example',
            artifactId: 'parent',
            version: '3.0.0',
          ),
          dependencies: [
            Dependency(
              groupId: 'org.example',
              artifactId: 'sibling',
              version: r'${project.parent.version}',
            ),
          ],
        );

        final effective = interpolator.interpolate(pom);

        expect(effective.dependencies[0].version, '3.0.0');
      });
    });

    group('interpolate - parent chain properties', () {
      test('child properties override parent properties', () {
        final parentPom = Pom(
          groupId: 'org.example',
          artifactId: 'parent',
          version: '1.0.0',
          properties: {
            'lib.version': '1.0.0',
          },
        );

        final childPom = Pom(
          artifactId: 'child',
          parent: ParentRef(
            groupId: 'org.example',
            artifactId: 'parent',
            version: '1.0.0',
          ),
          properties: {
            'lib.version': '2.0.0', // Override
          },
          dependencies: [
            Dependency(
              groupId: 'org.example',
              artifactId: 'lib',
              version: r'${lib.version}',
            ),
          ],
        );

        final effective = interpolator.interpolate(
          childPom,
          parentChain: [parentPom],
        );

        expect(effective.dependencies[0].version, '2.0.0');
      });

      test('inherits properties from parent when not overridden', () {
        final parentPom = Pom(
          groupId: 'org.example',
          artifactId: 'parent',
          version: '1.0.0',
          properties: {
            'parent.only.prop': 'from-parent',
          },
        );

        final childPom = Pom(
          artifactId: 'child',
          parent: ParentRef(
            groupId: 'org.example',
            artifactId: 'parent',
            version: '1.0.0',
          ),
          dependencies: [
            Dependency(
              groupId: 'org.example',
              artifactId: 'lib',
              version: r'${parent.only.prop}',
            ),
          ],
        );

        final effective = interpolator.interpolate(
          childPom,
          parentChain: [parentPom],
        );

        expect(effective.dependencies[0].version, 'from-parent');
      });

      test('merges properties from entire parent chain', () {
        final grandparent = Pom(
          groupId: 'org.example',
          artifactId: 'grandparent',
          version: '1.0.0',
          properties: {
            'grandparent.prop': 'from-grandparent',
          },
        );

        final parent = Pom(
          artifactId: 'parent',
          parent: ParentRef(
            groupId: 'org.example',
            artifactId: 'grandparent',
            version: '1.0.0',
          ),
          properties: {
            'parent.prop': 'from-parent',
          },
        );

        final child = Pom(
          artifactId: 'child',
          parent: ParentRef(
            groupId: 'org.example',
            artifactId: 'parent',
            version: '1.0.0',
          ),
          properties: {
            'child.prop': 'from-child',
          },
        );

        final effective = interpolator.interpolate(
          child,
          parentChain: [parent, grandparent],
        );

        expect(effective.properties['grandparent.prop'], 'from-grandparent');
        expect(effective.properties['parent.prop'], 'from-parent');
        expect(effective.properties['child.prop'], 'from-child');
      });
    });

    group('interpolate - dependencyManagement', () {
      test('merges dependencyManagement from parent chain', () {
        final parent = Pom(
          groupId: 'org.example',
          artifactId: 'parent',
          version: '1.0.0',
          dependencyManagement: [
            Dependency(
              groupId: 'org.example',
              artifactId: 'lib-a',
              version: '1.0.0',
            ),
          ],
        );

        final child = Pom(
          artifactId: 'child',
          parent: ParentRef(
            groupId: 'org.example',
            artifactId: 'parent',
            version: '1.0.0',
          ),
          dependencyManagement: [
            Dependency(
              groupId: 'org.example',
              artifactId: 'lib-b',
              version: '2.0.0',
            ),
          ],
        );

        final effective = interpolator.interpolate(
          child,
          parentChain: [parent],
        );

        expect(effective.dependencyManagement.length, 2);
      });

      test('child dependencyManagement overrides parent', () {
        final parent = Pom(
          groupId: 'org.example',
          artifactId: 'parent',
          version: '1.0.0',
          dependencyManagement: [
            Dependency(
              groupId: 'org.example',
              artifactId: 'lib',
              version: '1.0.0',
            ),
          ],
        );

        final child = Pom(
          artifactId: 'child',
          parent: ParentRef(
            groupId: 'org.example',
            artifactId: 'parent',
            version: '1.0.0',
          ),
          dependencyManagement: [
            Dependency(
              groupId: 'org.example',
              artifactId: 'lib',
              version: '2.0.0', // Override
            ),
          ],
        );

        final effective = interpolator.interpolate(
          child,
          parentChain: [parent],
        );

        expect(effective.dependencyManagement.length, 1);
        expect(effective.dependencyManagement[0].version, '2.0.0');
      });
    });

    group('interpolate - with properties fixture', () {
      test('interpolates all property types', () {
        final file = File('test/pom/fixtures/with_properties.pom.xml');
        final pom = parser.parseString(file.readAsStringSync());

        // Create mock parent for project.parent.version
        final parent = Pom(
          groupId: 'org.example',
          artifactId: 'parent',
          version: '1.0.0',
        );

        final effective = interpolator.interpolate(pom, parentChain: [parent]);

        // Check that dependencies got interpolated
        final dep = effective.dependencies[0];
        expect(dep.groupId, 'com.example');
        expect(dep.artifactId, 'my-lib');
        expect(dep.version, '2.0.0');
      });
    });

    group('interpolate - environment variables', () {
      test('resolves env.* properties', () {
        final pom = Pom(
          artifactId: 'test',
          description: r'Home: ${env.HOME}',
        );

        final effective = interpolator.interpolate(pom);

        // HOME should be set on all platforms
        expect(effective.pom.description, isNot(contains(r'${env.HOME}')));
      });
    });

    group('DependencyManagementApplier', () {
      late DependencyManagementApplier applier;

      setUp(() {
        applier = const DependencyManagementApplier();
      });

      test('fills in missing version from management', () {
        final dependencies = [
          Dependency(
            groupId: 'org.example',
            artifactId: 'lib',
          ),
        ];

        final management = [
          Dependency(
            groupId: 'org.example',
            artifactId: 'lib',
            version: '1.0.0',
          ),
        ];

        final result = applier.apply(dependencies, management);

        expect(result[0].version, '1.0.0');
      });

      test('does not override explicit version', () {
        final dependencies = [
          Dependency(
            groupId: 'org.example',
            artifactId: 'lib',
            version: '2.0.0',
          ),
        ];

        final management = [
          Dependency(
            groupId: 'org.example',
            artifactId: 'lib',
            version: '1.0.0',
          ),
        ];

        final result = applier.apply(dependencies, management);

        expect(result[0].version, '2.0.0');
      });

      test('merges exclusions', () {
        final dependencies = [
          Dependency(
            groupId: 'org.example',
            artifactId: 'lib',
            exclusions: [
              Exclusion(groupId: 'a', artifactId: 'a'),
            ],
          ),
        ];

        final management = [
          Dependency(
            groupId: 'org.example',
            artifactId: 'lib',
            version: '1.0.0',
            exclusions: [
              Exclusion(groupId: 'b', artifactId: 'b'),
            ],
          ),
        ];

        final result = applier.apply(dependencies, management);

        expect(result[0].exclusions.length, 2);
      });

      test('leaves unmanaged dependencies unchanged', () {
        final dependencies = [
          Dependency(
            groupId: 'org.example',
            artifactId: 'unmanaged',
            version: '1.0.0',
          ),
        ];

        final management = [
          Dependency(
            groupId: 'org.example',
            artifactId: 'other',
            version: '2.0.0',
          ),
        ];

        final result = applier.apply(dependencies, management);

        expect(result[0].version, '1.0.0');
      });
    });
  });
}
