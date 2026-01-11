import 'dart:io';

import 'package:maven_resolver/maven_resolver.dart';
import 'package:test/test.dart';

void main() {
  group('PomParser', () {
    late PomParser parser;

    setUp(() {
      parser = const PomParser();
    });

    group('parseString - simple POM', () {
      late Pom pom;

      setUpAll(() {
        final file = File('test/pom/fixtures/simple.pom.xml');
        pom = const PomParser().parseString(file.readAsStringSync());
      });

      test('parses basic fields', () {
        expect(pom.modelVersion, '4.0.0');
        expect(pom.groupId, 'org.example');
        expect(pom.artifactId, 'simple-project');
        expect(pom.version, '1.0.0');
        expect(pom.packaging, 'jar');
      });

      test('parses metadata fields', () {
        expect(pom.name, 'Simple Project');
        expect(pom.description, 'A simple test POM');
        expect(pom.url, 'https://example.org/simple');
      });

      test('parses properties', () {
        expect(pom.properties['java.version'], '11');
        expect(pom.properties['project.build.sourceEncoding'], 'UTF-8');
      });

      test('parses dependencies', () {
        expect(pom.dependencies.length, 2);

        final guava = pom.dependencies[0];
        expect(guava.groupId, 'com.google.guava');
        expect(guava.artifactId, 'guava');
        expect(guava.version, '31.0-jre');
        expect(guava.scope, DependencyScope.compile);

        final junit = pom.dependencies[1];
        expect(junit.groupId, 'junit');
        expect(junit.artifactId, 'junit');
        expect(junit.version, '4.13.2');
        expect(junit.scope, DependencyScope.test);
      });

      test('has no parent', () {
        expect(pom.parent, isNull);
        expect(pom.hasParent, isFalse);
      });
    });

    group('parseString - with parent', () {
      late Pom pom;

      setUpAll(() {
        final file = File('test/pom/fixtures/with_parent.pom.xml');
        pom = const PomParser().parseString(file.readAsStringSync());
      });

      test('parses parent reference', () {
        expect(pom.hasParent, isTrue);
        expect(pom.parent!.groupId, 'org.example');
        expect(pom.parent!.artifactId, 'parent-project');
        expect(pom.parent!.version, '2.0.0');
        expect(pom.parent!.relativePath, '../parent/pom.xml');
      });

      test('child has no explicit groupId/version', () {
        expect(pom.groupId, isNull);
        expect(pom.version, isNull);
      });

      test('effectiveGroupId comes from parent', () {
        expect(pom.effectiveGroupId, 'org.example');
        expect(pom.effectiveVersion, '2.0.0');
      });

      test('parses child properties', () {
        expect(pom.properties['custom.version'], '1.5.0');
      });
    });

    group('parseString - parent POM', () {
      late Pom pom;

      setUpAll(() {
        final file = File('test/pom/fixtures/parent.pom.xml');
        pom = const PomParser().parseString(file.readAsStringSync());
      });

      test('parses packaging as pom', () {
        expect(pom.packaging, 'pom');
      });

      test('parses dependencyManagement', () {
        expect(pom.dependencyManagement.length, 2);

        final commons = pom.dependencyManagement[0];
        expect(commons.groupId, 'org.apache.commons');
        expect(commons.artifactId, 'commons-lang3');
        expect(commons.version, r'${commons.version}');

        final slf4j = pom.dependencyManagement[1];
        expect(slf4j.groupId, 'org.slf4j');
        expect(slf4j.artifactId, 'slf4j-api');
        expect(slf4j.version, '1.7.36');
      });
    });

    group('parseString - with BOM', () {
      late Pom pom;

      setUpAll(() {
        final file = File('test/pom/fixtures/with_bom.pom.xml');
        pom = const PomParser().parseString(file.readAsStringSync());
      });

      test('parses BOM import', () {
        final bomImports = pom.bomImports;
        expect(bomImports.length, 1);

        final springBom = bomImports[0];
        expect(springBom.groupId, 'org.springframework.boot');
        expect(springBom.artifactId, 'spring-boot-dependencies');
        expect(springBom.version, r'${spring.boot.version}');
        expect(springBom.type, 'pom');
        expect(springBom.scope, DependencyScope.import_);
        expect(springBom.isBomImport, isTrue);
      });

      test('parses local override in dependencyManagement', () {
        final jackson = pom.dependencyManagement
            .firstWhere((d) => d.artifactId == 'jackson-databind');
        expect(jackson.version, '2.14.0');
        expect(jackson.isBomImport, isFalse);
      });
    });

    group('parseString - complex dependencies', () {
      late Pom pom;

      setUpAll(() {
        final file = File('test/pom/fixtures/complex_deps.pom.xml');
        pom = const PomParser().parseString(file.readAsStringSync());
      });

      test('parses dependency with classifier', () {
        final dep = pom.dependencies
            .firstWhere((d) => d.artifactId == 'lib-with-classifier');
        expect(dep.classifier, 'jdk11');
      });

      test('parses dependency with type', () {
        final dep =
            pom.dependencies.firstWhere((d) => d.artifactId == 'android-lib');
        expect(dep.type, 'aar');
      });

      test('parses optional dependency', () {
        final dep =
            pom.dependencies.firstWhere((d) => d.artifactId == 'optional-lib');
        expect(dep.optional, isTrue);
      });

      test('parses exclusions', () {
        final dep =
            pom.dependencies.firstWhere((d) => d.artifactId == 'slf4j-api');
        expect(dep.exclusions.length, 1);
        expect(dep.exclusions[0].groupId, 'org.slf4j');
        expect(dep.exclusions[0].artifactId, 'slf4j-log4j12');
      });

      test('parses wildcard exclusion', () {
        final dep = pom.dependencies
            .firstWhere((d) => d.artifactId == 'lib-with-bad-transitives');
        expect(dep.exclusions.length, 1);
        expect(dep.exclusions[0].isWildcard, isTrue);
      });

      test('parses system scope with systemPath', () {
        final dep = pom.dependencies.firstWhere((d) => d.artifactId == 'ojdbc');
        expect(dep.scope, DependencyScope.system);
        expect(dep.systemPath, r'${project.basedir}/lib/ojdbc.jar');
      });

      test('parses provided scope', () {
        final dep =
            pom.dependencies.firstWhere((d) => d.artifactId == 'servlet-api');
        expect(dep.scope, DependencyScope.provided);
      });

      test('parses runtime scope', () {
        final dep = pom.dependencies
            .firstWhere((d) => d.artifactId == 'mysql-connector-java');
        expect(dep.scope, DependencyScope.runtime);
      });
    });

    group('parseString - relocation', () {
      late Pom pom;

      setUpAll(() {
        final file = File('test/pom/fixtures/relocated.pom.xml');
        pom = const PomParser().parseString(file.readAsStringSync());
      });

      test('parses relocation info', () {
        expect(pom.distributionManagement, isNotNull);
        final relocation = pom.distributionManagement!.relocation;
        expect(relocation, isNotNull);
        expect(relocation!.groupId, 'new.group');
        expect(relocation.artifactId, 'new-artifact');
        expect(relocation.version, '2.0.0');
        expect(relocation.message, contains('moved'));
        expect(relocation.isEffective, isTrue);
      });
    });

    group('parseString - error handling', () {
      test('throws on invalid XML', () {
        expect(
          () => parser.parseString('not xml'),
          throwsA(isA<PomParseException>()),
        );
      });

      test('throws on wrong root element', () {
        expect(
          () => parser.parseString('<settings></settings>'),
          throwsA(isA<PomParseException>()),
        );
      });

      test('throws on missing artifactId', () {
        expect(
          () => parser.parseString('''
<project>
  <groupId>org.example</groupId>
  <version>1.0.0</version>
</project>
'''),
          throwsA(isA<PomParseException>()),
        );
      });

      test('handles minimal valid POM', () {
        final pom = parser.parseString('''
<project>
  <artifactId>minimal</artifactId>
</project>
''');
        expect(pom.artifactId, 'minimal');
        expect(pom.groupId, isNull);
        expect(pom.version, isNull);
        expect(pom.packaging, 'jar');
      });
    });

    group('Dependency model', () {
      test('conflictKey without classifier', () {
        const dep = Dependency(
          groupId: 'org.example',
          artifactId: 'my-lib',
          version: '1.0.0',
        );
        expect(dep.conflictKey, 'org.example:my-lib');
      });

      test('conflictKey with classifier', () {
        const dep = Dependency(
          groupId: 'org.example',
          artifactId: 'my-lib',
          version: '1.0.0',
          classifier: 'sources',
        );
        expect(dep.conflictKey, 'org.example:my-lib:sources');
      });

      test('coordinate formatting', () {
        const dep = Dependency(
          groupId: 'org.example',
          artifactId: 'my-lib',
          version: '1.0.0',
        );
        expect(dep.coordinate, 'org.example:my-lib:1.0.0');
      });

      test('isBomImport', () {
        const bomImport = Dependency(
          groupId: 'org.example',
          artifactId: 'bom',
          version: '1.0.0',
          type: 'pom',
          scope: DependencyScope.import_,
        );
        expect(bomImport.isBomImport, isTrue);

        const normalDep = Dependency(
          groupId: 'org.example',
          artifactId: 'lib',
          version: '1.0.0',
        );
        expect(normalDep.isBomImport, isFalse);
      });
    });

    group('scopeExplicit tracking', () {
      test('scope is explicit when <scope> element is present', () {
        final pom = parser.parseString('''
<project>
  <artifactId>test</artifactId>
  <dependencies>
    <dependency>
      <groupId>org.example</groupId>
      <artifactId>lib</artifactId>
      <version>1.0.0</version>
      <scope>runtime</scope>
    </dependency>
  </dependencies>
</project>
''');
        expect(pom.dependencies[0].scope, DependencyScope.runtime);
        expect(pom.dependencies[0].scopeExplicit, isTrue);
      });

      test('scope is not explicit when <scope> element is absent', () {
        final pom = parser.parseString('''
<project>
  <artifactId>test</artifactId>
  <dependencies>
    <dependency>
      <groupId>org.example</groupId>
      <artifactId>lib</artifactId>
      <version>1.0.0</version>
    </dependency>
  </dependencies>
</project>
''');
        expect(pom.dependencies[0].scope, DependencyScope.compile);
        expect(pom.dependencies[0].scopeExplicit, isFalse);
      });

      test('scopeExplicit is tracked in dependencyManagement', () {
        final pom = parser.parseString('''
<project>
  <artifactId>test</artifactId>
  <dependencyManagement>
    <dependencies>
      <dependency>
        <groupId>org.example</groupId>
        <artifactId>lib</artifactId>
        <version>1.0.0</version>
        <scope>provided</scope>
      </dependency>
    </dependencies>
  </dependencyManagement>
</project>
''');
        expect(pom.dependencyManagement[0].scope, DependencyScope.provided);
        expect(pom.dependencyManagement[0].scopeExplicit, isTrue);
      });
    });

    group('DependencyScope', () {
      test('parse handles all scopes', () {
        expect(DependencyScope.parse('compile'), DependencyScope.compile);
        expect(DependencyScope.parse('provided'), DependencyScope.provided);
        expect(DependencyScope.parse('runtime'), DependencyScope.runtime);
        expect(DependencyScope.parse('test'), DependencyScope.test);
        expect(DependencyScope.parse('system'), DependencyScope.system);
        expect(DependencyScope.parse('import'), DependencyScope.import_);
      });

      test('parse defaults to compile', () {
        expect(DependencyScope.parse(null), DependencyScope.compile);
        expect(DependencyScope.parse(''), DependencyScope.compile);
        expect(DependencyScope.parse('unknown'), DependencyScope.compile);
      });

      test('isTransitive', () {
        expect(DependencyScope.compile.isTransitive, isTrue);
        expect(DependencyScope.runtime.isTransitive, isTrue);
        expect(DependencyScope.provided.isTransitive, isFalse);
        expect(DependencyScope.test.isTransitive, isFalse);
        expect(DependencyScope.system.isTransitive, isFalse);
      });
    });

    group('Exclusion', () {
      test('matches exact', () {
        const exclusion = Exclusion(groupId: 'org.example', artifactId: 'lib');
        expect(exclusion.matches('org.example', 'lib'), isTrue);
        expect(exclusion.matches('org.example', 'other'), isFalse);
        expect(exclusion.matches('other.group', 'lib'), isFalse);
      });

      test('matches with wildcards', () {
        const groupWildcard = Exclusion(groupId: '*', artifactId: 'lib');
        expect(groupWildcard.matches('any.group', 'lib'), isTrue);
        expect(groupWildcard.matches('any.group', 'other'), isFalse);

        const artifactWildcard =
            Exclusion(groupId: 'org.example', artifactId: '*');
        expect(artifactWildcard.matches('org.example', 'any'), isTrue);
        expect(artifactWildcard.matches('other', 'any'), isFalse);

        expect(Exclusion.all.matches('any', 'thing'), isTrue);
      });
    });

    group('ExclusionSet', () {
      test('matches any exclusion', () {
        final set = ExclusionSet([
          const Exclusion(groupId: 'org.a', artifactId: 'a'),
          const Exclusion(groupId: 'org.b', artifactId: 'b'),
        ]);
        expect(set.matches('org.a', 'a'), isTrue);
        expect(set.matches('org.b', 'b'), isTrue);
        expect(set.matches('org.c', 'c'), isFalse);
      });

      test('empty set matches nothing', () {
        expect(ExclusionSet.empty.matches('any', 'thing'), isFalse);
        expect(ExclusionSet.empty.isEmpty, isTrue);
      });

      test('merge combines sets', () {
        final set1 =
            ExclusionSet([const Exclusion(groupId: 'a', artifactId: 'a')]);
        final set2 =
            set1.merge([const Exclusion(groupId: 'b', artifactId: 'b')]);
        expect(set2.matches('a', 'a'), isTrue);
        expect(set2.matches('b', 'b'), isTrue);
      });
    });

    group('scope mediation', () {
      test('compile + compile = compile', () {
        expect(
          mediateScope(DependencyScope.compile, DependencyScope.compile),
          DependencyScope.compile,
        );
      });

      test('compile + runtime = runtime', () {
        expect(
          mediateScope(DependencyScope.compile, DependencyScope.runtime),
          DependencyScope.runtime,
        );
      });

      test('provided + compile = provided', () {
        expect(
          mediateScope(DependencyScope.provided, DependencyScope.compile),
          DependencyScope.provided,
        );
      });

      test('test + compile = test', () {
        expect(
          mediateScope(DependencyScope.test, DependencyScope.compile),
          DependencyScope.test,
        );
      });

      test('any + provided = null (omitted)', () {
        expect(
          mediateScope(DependencyScope.compile, DependencyScope.provided),
          isNull,
        );
      });

      test('any + test = null (omitted)', () {
        expect(
          mediateScope(DependencyScope.compile, DependencyScope.test),
          isNull,
        );
      });
    });
  });
}
