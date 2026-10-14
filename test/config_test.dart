@Timeout(Duration(minutes: 3))
library;

import 'dart:io';

import 'package:test/test.dart';

import 'support/fixtures.dart';
import 'support/project.dart';

void main() {
  group('exit code', () {
    test('is non-zero for an unknown command', () async {
      final result = await rush(['nonexistent'],
          workingDirectory: Directory.systemTemp.path);
      expect(result.exitCode, isNot(0));
    });

    test('is non-zero and explained when building outside a project', () async {
      final empty = await Directory.systemTemp.createTemp('rush-test-empty-');
      addTearDown(() => empty.delete(recursive: true));
      final result = await rush(['build'], workingDirectory: empty.path);
      expect(result.exitCode, isNot(0));
      expect(result.output, contains('rush.yml'));
    });

    test('is non-zero when the build fails', () async {
      final project = await TestProject.create('broken_ext');
      project.source('${project.className}.java').writeAsStringSync('not java');
      final result = await project.build();
      expect(result.exitCode, isNot(0));
      expect(result.output, contains('BUILD FAILED'));
    });
  });

  group('errors', () {
    Future<String> failedBuild(TestProject project) async {
      final result = await project.build();
      expect(result.exitCode, 1, reason: result.output);
      expect(result.output, isNot(contains('Exception')));
      return result.output;
    }

    test('explain that no class has @Extension', () async {
      final project = await TestProject.create('unannotated_ext');
      project.editSource(
          '${project.className}.java', RegExp(r'@Extension\([^)]*\)'), '');
      expect(await failedBuild(project), contains('@Extension'));
    });

    test('point at the rush.yml line of a configuration mistake', () async {
      final project = await TestProject.create('typo_ext');
      project.editConfig('min_sdk:', 'min_sdkk:');
      expect(
          await failedBuild(project),
          allOf(
              contains('rush.yml'), contains('line 7'), contains('min_sdkk')));
    });

    test('reject excluding a library rush.yml depends on directly', () async {
      final project = await TestProject.create('excluded_direct_ext');
      project.addDependencies(['com.google.code.gson:gson:2.8.9']);
      project.placeLibraries({'com.google.code.gson:gson': 'exclude'});
      expect(
          await failedBuild(project),
          allOf(contains('rush.yml'), contains('com.google.code.gson:gson'),
              contains('dependencies')));
    });

    test('name the placements a library can have', () async {
      final project = await TestProject.create('placement_typo_ext');
      project.placeLibraries({'com.google.code.gson:gson': 'bundled'});
      expect(
          await failedBuild(project),
          allOf(contains('bundled'), contains('exclude'), contains('provided'),
              contains('shared'), contains('private')));
    });

    test('name a missing asset', () async {
      final project = await TestProject.create('no_asset_ext');
      project.editConfig('#assets:', 'assets:\n- missing.txt\n#assets:');
      expect(await failedBuild(project), contains('assets/missing.txt'));
    });

    test('name a missing local library', () async {
      final project = await TestProject.create('no_jar_ext');
      project.editConfig('#dependencies:', 'dependencies:\n- missing.jar');
      expect(await failedBuild(project), contains('deps/missing.jar'));
    });

    test('list unresolvable dependencies', () async {
      final project = await TestProject.create('no_artifact_ext');
      project.addDependencies(['com.example.missing:nothing:9.9.9']);
      expect(await failedBuild(project),
          contains('com.example.missing:nothing:9.9.9'));
    });

    test('explain that the build needs a JDK', () async {
      final project = await TestProject.create('no_jdk_ext');
      final missingJdk = '${project.dir.path}${Platform.pathSeparator}no-jdk';
      final result = await project.build([], {'JAVA_HOME': missingJdk});
      expect(result.exitCode, 1, reason: result.output);
      expect(result.output, contains('Could not run `$missingJdk'));
      expect(result.output, contains('Rush needs JDK 17 or newer'));
    });
  });

  group('output', () {
    final escape = RegExp('\x1b');

    group('of a build written to a pipe', () {
      late ProcessResult build;

      setUpAll(() async {
        final project = await TestProject.create('piped_ext');
        final config = project.file('rush.yml');
        config.writeAsStringSync(
            '${config.readAsStringSync()}\nauthors:\n- Jane Doe\ndesugar: true\n');
        build = await Process.run(rushBin, ['build'],
            workingDirectory: project.dir.path);
        if (build.exitCode != 0) fail(build.output);
      });

      test('is plain text', () {
        expect(build.output, isNot(contains(escape)));
        expect(build.output, isNot(contains('/_/')));
        expect(build.output, contains('Compiling sources'));
        expect(build.output, isNot(contains(RegExp(r' $', multiLine: true))));
      });

      test('warns about rush.yml keys that have no effect', () {
        expect(build.output, contains('`authors` in rush.yml has no effect'));
        expect(build.output, contains('`desugar` in rush.yml has no effect'));
      });
    });

    test('is colored when color is requested', () async {
      final result = await Process.run(rushBin, ['--color', 'clean'],
          workingDirectory: Directory.systemTemp.path);
      expect(result.output, contains(escape));
    });

    test('of clean is plain text when not written to a terminal', () async {
      final project = await TestProject.create('clean_ext');
      final result = await Process.run(rushBin, ['clean'],
          workingDirectory: project.dir.path);
      expect(result.exitCode, 0, reason: result.output);
      expect(result.output, isNot(contains(escape)));
      expect(result.output, contains('Deleted build files and caches'));
    });
  });
}
