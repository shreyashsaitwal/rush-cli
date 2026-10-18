import 'dart:convert';

import 'package:maven_resolver/maven_resolver.dart';
import 'package:test/test.dart';

import 'mock_repository.dart';

const _group = 'com.example';
const _version = '1.0.0';

void main() {
  late MockRepository repo;

  setUp(() {
    repo = MockRepository();
    _publishRoot(repo, 'core',
        platforms: {'androidJvm': 'core-android', 'jvm': 'core-jvm'});
    _publishVariant(repo, 'core-android', root: 'core', packaging: 'aar');
    _publishVariant(repo, 'core-jvm', root: 'core');
  });

  Future<List<String>> resolve(String artifactId) async {
    final result = await DependencyResolver(repository: repo).resolve(
      directDependencies: [
        Dependency(groupId: _group, artifactId: artifactId, version: _version),
      ],
    );
    expect(result.errors, isEmpty);
    return [
      for (final artifact in result.artifacts) artifact.coordinate.artifactId
    ]..sort();
  }

  test('a declared multiplatform root resolves through its POM', () async {
    expect(await resolve('core'), ['core', 'core-android']);
  });

  test('a platform variant depends on the roots its module names', () async {
    _publishVariant(repo, 'store-jvm',
        root: 'store',
        pomDependencies: ['core-jvm'],
        runtimeDependencies: ['core']);

    expect(await resolve('store-jvm'), ['core', 'core-android', 'store-jvm']);
  });

  test('a platform variant without a runtime variant keeps its POM', () async {
    repo.addPom(_group, 'docs-jvm', _version,
        _pom('docs-jvm', dependencies: ['core-jvm']));
    repo.addFile(
        _modulePath('docs-jvm'),
        _module(component: {
          'url': '../../docs/$_version/docs-$_version.module',
        }, variants: []));

    expect(await resolve('docs-jvm'), ['core-jvm', 'docs-jvm']);
  });

  test('a platform variant skips the platforms its module names', () async {
    _publishVariant(repo, 'store-jvm',
        root: 'store', runtimeDependencies: ['core']);
    final module = jsonDecode(repo.files[_modulePath('store-jvm')]!)
        as Map<String, dynamic>;
    final runtime = (module['variants'] as List).last as Map<String, dynamic>;
    (runtime['dependencies'] as List).add({
      ..._dependency('bom'),
      'attributes': {'org.gradle.category': 'platform'},
    });
    repo.addFile(_modulePath('store-jvm'), jsonEncode(module));

    expect(await resolve('store-jvm'), ['core', 'core-android', 'store-jvm']);
  });

  test('a module of the wrong shape leaves the POM in charge', () async {
    repo.addPom(_group, 'odd-jvm', _version,
        _pom('odd-jvm', dependencies: ['core-jvm']));
    repo.addFile(_modulePath('odd-jvm'), '{"component": {"url": 1}}');

    expect(await resolve('odd-jvm'), ['core-jvm', 'odd-jvm']);
  });

  test('module dependencies in the API variant are compile scope', () async {
    _publishVariant(repo, 'tool', root: 'toolkit');
    _publishVariant(repo, 'helper', root: 'helpers');
    _publishVariant(repo, 'store-jvm',
        root: 'store',
        runtimeDependencies: ['tool', 'helper'],
        apiDependencies: ['tool']);

    final result = await DependencyResolver(repository: repo).resolve(
      directDependencies: [
        const Dependency(
            groupId: _group, artifactId: 'store-jvm', version: _version),
      ],
    );

    final scopes = {
      for (final artifact in result.artifacts)
        artifact.coordinate.artifactId: artifact.scope,
    };
    expect(scopes['tool'], DependencyScope.compile);
    expect(scopes['helper'], DependencyScope.runtime);
  });

  test('POMs without the Gradle metadata marker keep their dependencies',
      () async {
    repo.addSimplePom(_group, 'legacy', _version,
        dependencies: ['$_group:core-jvm:$_version']);
    repo.addFile(
        _modulePath('legacy'),
        _module(component: {}, variants: [
          _runtimeVariant('jvm', dependencies: ['core']),
        ]));

    expect(await resolve('legacy'), ['core-jvm', 'legacy']);
  });

  test('a marked POM without a module keeps its dependencies', () async {
    repo.addPom(_group, 'unpublished', _version,
        _pom('unpublished', dependencies: ['core-jvm']));

    expect(await resolve('unpublished'), ['core-jvm', 'unpublished']);
  });
}

String _modulePath(String artifactId) =>
    '${_group.replaceAll('.', '/')}/$artifactId/$_version/$artifactId-$_version.module';

void _publishRoot(MockRepository repo, String artifactId,
    {required Map<String, String> platforms}) {
  repo.addPom(_group, artifactId, _version,
      _pom(artifactId, dependencies: platforms.values.take(1).toList()));
  repo.addFile(
      _modulePath(artifactId),
      _module(component: {}, variants: [
        {
          'name': 'metadataApiElements',
          'attributes': {
            'org.gradle.usage': 'kotlin-metadata',
            'org.jetbrains.kotlin.platform.type': 'common'
          },
          'dependencies': [_dependency('unrelated')],
        },
        for (final MapEntry(key: platform, value: variant) in platforms.entries)
          for (final usage in ['java-api', 'java-runtime'])
            {
              'name': '$platform-$usage',
              'attributes': {
                'org.gradle.category': 'library',
                'org.gradle.usage': usage,
                'org.jetbrains.kotlin.platform.type': platform,
              },
              'available-at': {
                'url': '../../$variant/$_version/$variant-$_version.module',
                'group': _group,
                'module': variant,
                'version': _version,
              },
            },
      ]));
}

void _publishVariant(MockRepository repo, String artifactId,
    {required String root,
    String packaging = 'jar',
    List<String> pomDependencies = const [],
    List<String> runtimeDependencies = const [],
    List<String> apiDependencies = const []}) {
  repo.addPom(_group, artifactId, _version,
      _pom(artifactId, packaging: packaging, dependencies: pomDependencies));
  repo.addFile(
      _modulePath(artifactId),
      _module(component: {
        'url': '../../$root/$_version/$root-$_version.module',
        'group': _group,
        'module': root,
        'version': _version,
      }, variants: [
        {
          'name': 'jvmApiElements',
          'attributes': {
            'org.gradle.category': 'library',
            'org.gradle.usage': 'java-api',
            'org.jetbrains.kotlin.platform.type': 'jvm',
          },
          'dependencies': [
            for (final name in apiDependencies) _dependency(name)
          ],
        },
        _runtimeVariant('jvm', dependencies: runtimeDependencies),
      ]));
}

Map<String, Object> _runtimeVariant(String platform,
        {required List<String> dependencies}) =>
    {
      'name': '${platform}RuntimeElements',
      'attributes': {
        'org.gradle.category': 'library',
        'org.gradle.usage': 'java-runtime',
        'org.jetbrains.kotlin.platform.type': platform,
      },
      'dependencies': [for (final name in dependencies) _dependency(name)],
    };

Map<String, Object> _dependency(String artifactId) => {
      'group': _group,
      'module': artifactId,
      'version': {'requires': _version},
    };

String _module(
        {required Map<String, String> component,
        required List<Map<String, Object>> variants}) =>
    jsonEncode({
      'formatVersion': '1.1',
      'component': {
        'group': _group,
        'module': 'unused',
        'version': _version,
        ...component
      },
      'variants': variants,
    });

String _pom(String artifactId,
        {String packaging = 'jar', List<String> dependencies = const []}) =>
    '''
<project>
  <!-- do_not_remove: published-with-gradle-metadata -->
  <modelVersion>4.0.0</modelVersion>
  <groupId>$_group</groupId>
  <artifactId>$artifactId</artifactId>
  <version>$_version</version>
  <packaging>$packaging</packaging>
  <dependencies>
${[
      for (final name in dependencies)
        '    <dependency><groupId>$_group</groupId><artifactId>$name</artifactId><version>$_version</version></dependency>'
    ].join('\n')}
  </dependencies>
</project>
''';
