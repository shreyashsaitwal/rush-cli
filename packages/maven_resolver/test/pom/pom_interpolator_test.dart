import 'dart:io';

import 'package:maven_resolver/maven_resolver.dart';
import 'package:test/test.dart';

void main() {
  group('PomInterpolator', () {
    late PomInterpolator interpolator;
    late PomParser parser;

    setUp(() {
      interpolator = PomInterpolator();
      parser = const PomParser();
    });

    group('interpolate - basic properties', () {
      test('resolves simple property reference', () {
        const pom = Pom(
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
        const pom = Pom(
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
        const pom = Pom(
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
        const pom = Pom(
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
        const pom = Pom(
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
        const pom = Pom(
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
        const pom = Pom(
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
        const pom = Pom(
          groupId: 'org.example',
          artifactId: 'my-project',
          version: '1.0.0',
          name: r'${project.artifactId}',
        );

        final effective = interpolator.interpolate(pom);

        expect(effective.pom.name, 'my-project');
      });

      test('resolves project.parent.version', () {
        const pom = Pom(
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
        const parentPom = Pom(
          groupId: 'org.example',
          artifactId: 'parent',
          version: '1.0.0',
          properties: {
            'lib.version': '1.0.0',
          },
        );

        const childPom = Pom(
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
        const parentPom = Pom(
          groupId: 'org.example',
          artifactId: 'parent',
          version: '1.0.0',
          properties: {
            'parent.only.prop': 'from-parent',
          },
        );

        const childPom = Pom(
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
        const grandparent = Pom(
          groupId: 'org.example',
          artifactId: 'grandparent',
          version: '1.0.0',
          properties: {
            'grandparent.prop': 'from-grandparent',
          },
        );

        const parent = Pom(
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

        const child = Pom(
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
        const parent = Pom(
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

        const child = Pom(
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
        const parent = Pom(
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

        const child = Pom(
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
        const parent = Pom(
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
        const pom = Pom(
          artifactId: 'test',
          description: r'Home: ${env.HOME}',
        );

        final effective = interpolator.interpolate(pom);

        // HOME should be set on all platforms
        expect(effective.pom.description, isNot(contains(r'${env.HOME}')));
      });
    });

    group('interpolate - project.basedir', () {
      test('resolves project.basedir', () {
        const pom = Pom(
          groupId: 'org.example',
          artifactId: 'test',
          version: '1.0.0',
          dependencies: [
            Dependency(
              groupId: 'org.example',
              artifactId: 'lib',
              version: '1.0.0',
              systemPath: r'${project.basedir}/lib/local.jar',
            ),
          ],
        );

        final effective = interpolator.interpolate(
          pom,
          basedir: '/home/user/project',
        );

        expect(
          effective.dependencies[0].systemPath,
          '/home/user/project/lib/local.jar',
        );
      });

      test('resolves project.build.directory', () {
        const pom = Pom(
          artifactId: 'test',
          description: r'Output: ${project.build.directory}',
        );

        final effective = interpolator.interpolate(
          pom,
          basedir: '/home/user/project',
        );

        expect(
          effective.pom.description,
          'Output: /home/user/project/target',
        );
      });

      test('resolves project.build.outputDirectory', () {
        const pom = Pom(
          artifactId: 'test',
          description: r'Classes: ${project.build.outputDirectory}',
        );

        final effective = interpolator.interpolate(
          pom,
          basedir: '/home/user/project',
        );

        expect(
          effective.pom.description,
          'Classes: /home/user/project/target/classes',
        );
      });

      test('resolves project.build.sourceDirectory', () {
        const pom = Pom(
          artifactId: 'test',
          description: r'Source: ${project.build.sourceDirectory}',
        );

        final effective = interpolator.interpolate(
          pom,
          basedir: '/home/user/project',
        );

        expect(
          effective.pom.description,
          'Source: /home/user/project/src/main/java',
        );
      });

      test('leaves project.basedir unresolved when basedir not provided', () {
        const pom = Pom(
          artifactId: 'test',
          description: r'${project.basedir}/lib',
        );

        final effective = interpolator.interpolate(pom);

        expect(
          effective.pom.description,
          r'${project.basedir}/lib',
        );
      });
    });

    group('interpolate - Java system properties', () {
      test('resolves os.name', () {
        const pom = Pom(
          artifactId: 'test',
          description: r'OS: ${os.name}',
        );

        final effective = interpolator.interpolate(pom);

        // Should be resolved to something (not the placeholder)
        expect(effective.pom.description, isNot(contains(r'${os.name}')));
        expect(
          effective.pom.description,
          anyOf(
            contains('Linux'),
            contains('Mac OS X'),
            contains('Windows'),
          ),
        );
      });

      test('resolves user.home', () {
        const pom = Pom(
          artifactId: 'test',
          description: r'Home: ${user.home}',
        );

        final effective = interpolator.interpolate(pom);

        expect(effective.pom.description, isNot(contains(r'${user.home}')));
      });

      test('resolves file.separator', () {
        const pom = Pom(
          artifactId: 'test',
          description: r'Sep: ${file.separator}',
        );

        final effective = interpolator.interpolate(pom);

        expect(
          effective.pom.description,
          anyOf(equals('Sep: /'), equals(r'Sep: \')),
        );
      });

      test('JavaSystemProperties.fromPlatform creates valid properties', () {
        final sysProps = JavaSystemProperties.fromPlatform();

        expect(sysProps.osName, isNotEmpty);
        expect(sysProps.osArch, isNotEmpty);
        expect(sysProps.fileSeparator, isNotEmpty);
        expect(sysProps.pathSeparator, isNotEmpty);
        expect(sysProps.lineSeparator, isNotEmpty);
        expect(sysProps.userDir, isNotEmpty);
      });

      test('JavaSystemProperties.getProperty returns correct values', () {
        const sysProps = JavaSystemProperties(
          javaVersion: '17',
          javaHome: '/usr/lib/jvm/java-17',
          osName: 'Linux',
          osArch: 'amd64',
          osVersion: '5.15.0',
          fileSeparator: '/',
          pathSeparator: ':',
          lineSeparator: '\n',
          userHome: '/home/testuser',
          userName: 'testuser',
          userDir: '/home/testuser/project',
        );

        expect(sysProps.getProperty('java.version'), '17');
        expect(sysProps.getProperty('java.home'), '/usr/lib/jvm/java-17');
        expect(sysProps.getProperty('os.name'), 'Linux');
        expect(sysProps.getProperty('os.arch'), 'amd64');
        expect(sysProps.getProperty('os.version'), '5.15.0');
        expect(sysProps.getProperty('file.separator'), '/');
        expect(sysProps.getProperty('path.separator'), ':');
        expect(sysProps.getProperty('line.separator'), '\n');
        expect(sysProps.getProperty('user.home'), '/home/testuser');
        expect(sysProps.getProperty('user.name'), 'testuser');
        expect(sysProps.getProperty('user.dir'), '/home/testuser/project');
        expect(sysProps.getProperty('unknown.prop'), isNull);
      });
    });

    group('DependencyManagementApplier', () {
      late DependencyManagementApplier applier;

      setUp(() {
        applier = const DependencyManagementApplier();
      });

      test('fills in missing version from management', () {
        final dependencies = [
          const Dependency(
            groupId: 'org.example',
            artifactId: 'lib',
          ),
        ];

        final management = [
          const Dependency(
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
          const Dependency(
            groupId: 'org.example',
            artifactId: 'lib',
            version: '2.0.0',
          ),
        ];

        final management = [
          const Dependency(
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
          const Dependency(
            groupId: 'org.example',
            artifactId: 'lib',
            exclusions: [
              Exclusion(groupId: 'a', artifactId: 'a'),
            ],
          ),
        ];

        final management = [
          const Dependency(
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
          const Dependency(
            groupId: 'org.example',
            artifactId: 'unmanaged',
            version: '1.0.0',
          ),
        ];

        final management = [
          const Dependency(
            groupId: 'org.example',
            artifactId: 'other',
            version: '2.0.0',
          ),
        ];

        final result = applier.apply(dependencies, management);

        expect(result[0].version, '1.0.0');
      });

      test(
          'applies scope from management when dependency scope is not explicit',
          () {
        final dependencies = [
          const Dependency(
            groupId: 'org.example',
            artifactId: 'lib',
            version: '1.0.0',
            scope: DependencyScope.compile,
            scopeExplicit: false, // Not explicitly set in XML
          ),
        ];

        final management = [
          const Dependency(
            groupId: 'org.example',
            artifactId: 'lib',
            version: '1.0.0',
            scope: DependencyScope.provided,
            scopeExplicit: true,
          ),
        ];

        final result = applier.apply(dependencies, management);

        expect(result[0].scope, DependencyScope.provided);
      });

      test('preserves explicit scope even when management has different scope',
          () {
        final dependencies = [
          const Dependency(
            groupId: 'org.example',
            artifactId: 'lib',
            version: '1.0.0',
            scope: DependencyScope.runtime,
            scopeExplicit: true, // Explicitly set in XML
          ),
        ];

        final management = [
          const Dependency(
            groupId: 'org.example',
            artifactId: 'lib',
            version: '1.0.0',
            scope: DependencyScope.provided,
            scopeExplicit: true,
          ),
        ];

        final result = applier.apply(dependencies, management);

        expect(result[0].scope, DependencyScope.runtime);
      });

      test('uses compile scope when neither dep nor management specify scope',
          () {
        final dependencies = [
          const Dependency(
            groupId: 'org.example',
            artifactId: 'lib',
            scope: DependencyScope.compile,
            scopeExplicit: false,
          ),
        ];

        final management = [
          const Dependency(
            groupId: 'org.example',
            artifactId: 'lib',
            version: '1.0.0',
            scope: DependencyScope.compile,
            scopeExplicit: false,
          ),
        ];

        final result = applier.apply(dependencies, management);

        expect(result[0].scope, DependencyScope.compile);
        expect(result[0].version, '1.0.0');
      });
    });
  });
}
