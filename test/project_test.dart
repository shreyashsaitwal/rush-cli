@Timeout(Duration(minutes: 3))
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:test/test.dart';

import 'support/fixtures.dart';
import 'support/project.dart';

void main() {
  group('create', () {
    group('makes projects that', () {
      late TestProject project;

      setUpAll(() async {
        project = await TestProject.create('template_ext');
      });

      test('leave repackaging to Rush', () {
        expect(
            project.file('src/proguard-rules.pro').readAsStringSync(),
            allOf(isNot(contains('-repackageclasses')),
                isNot(contains('-keeppackagenames'))));
      });

      test('target Android 5.0 (API 21)', () {
        expect(project.file('rush.yml').readAsStringSync(),
            contains('min_sdk: 21'));
      });

      test('have a GitHub workflow that builds with Rush', () {
        final workflow =
            project.file('.github/workflows/build.yml').readAsStringSync();
        expect(workflow, contains('uses: shreyashsaitwal/rush-cli@v2'));
        expect(workflow, contains('run: rush build'));
        expect(workflow, contains('workflow_dispatch:'));
        expect(workflow, contains('- src/**'));
      });

      test('have agent instructions', () {
        expect(project.file('AGENTS.md').readAsStringSync(),
            contains('.claude/skills/rush/SKILL.md'));
        expect(project.file('CLAUDE.md').readAsStringSync(), '@AGENTS.md\n');
        expect(project.file('.claude/skills/rush/SKILL.md').readAsStringSync(),
            startsWith('---\nname: rush\n'));
      });

      test('have a dev container and Copilot setup steps', () {
        final devcontainer = jsonDecode(project
            .file('.devcontainer/devcontainer.json')
            .readAsStringSync()) as Map<String, dynamic>;
        expect(devcontainer['features'],
            contains('ghcr.io/shreyashsaitwal/rush-cli/rush:1'));
        expect(devcontainer['postCreateCommand'], 'rush deps sync');
        expect(
            project
                .file('.github/workflows/copilot-setup-steps.yml')
                .readAsStringSync(),
            contains('copilot-setup-steps:'));
      });

      test('have VS Code project files', () {
        expect(project.file('.project').existsSync(), true);
        expect(project.file('.classpath').readAsStringSync(),
            contains('annotations.jar'));
        expect(project.file('.gitignore').readAsStringSync(),
            contains('/.classpath'));
      });

      test('keep IntelliJ machine paths out of git', () {
        expect(project.file('.gitignore').readAsStringSync(),
            contains('/.idea/libraries/'));
      });
    });

    test('asks for missing options only in a terminal', () async {
      final parent = await Directory.systemTemp.createTemp('rush-test-');
      addTearDown(() => parent.delete(recursive: true));
      final result = await rush(['create', 'prompt_ext', '-p', 'com.example'],
              workingDirectory: parent.path)
          .timeout(const Duration(seconds: 20));
      expect(result.exitCode, 64, reason: result.output);
      expect(result.output, contains('--language'));
    });

    test('asks for nothing when stdin is /dev/null', () async {
      final parent = await Directory.systemTemp.createTemp('rush-test-');
      addTearDown(() => parent.delete(recursive: true));
      final result = await Process.run(
              'sh',
              [
                '-c',
                '"\$0" --no-color create null_ext -p com.example -l java '
                    '< /dev/null',
                rushBin
              ],
              workingDirectory: parent.path)
          .timeout(const Duration(seconds: 20));
      expect(result.exitCode, 64, reason: result.output);
      expect(result.output, contains('Missing --ide'));
    }, testOn: '!windows');
  });

  group('agents', () {
    test('refreshes agent instructions without touching AGENTS.md', () async {
      final project = await TestProject.create('agent_refresh_ext');
      project.file('AGENTS.md').writeAsStringSync('My own notes\n');
      project.file('CLAUDE.md').deleteSync();
      final skill = project.file('.claude/skills/rush/SKILL.md')
        ..writeAsStringSync('outdated');

      final result = await rush(['agents'], workingDirectory: project.dir.path);
      expect(result.exitCode, 0, reason: result.output);
      expect(project.file('AGENTS.md').readAsStringSync(), 'My own notes\n');
      expect(project.file('CLAUDE.md').readAsStringSync(), '@AGENTS.md\n');
      expect(skill.readAsStringSync(), startsWith('---\nname: rush\n'));
    });

    test('adds the dev container and project files to existing projects',
        () async {
      final project = await TestProject.create('container_add_ext');
      project.file('.devcontainer/devcontainer.json').deleteSync();
      project.file('.github/workflows/copilot-setup-steps.yml').deleteSync();
      project.file('.project').deleteSync();
      project.file('.gitignore').writeAsStringSync('/out\n');

      final result = await rush(['agents'], workingDirectory: project.dir.path);
      expect(result.exitCode, 0, reason: result.output);
      expect(
          project.file('.devcontainer/devcontainer.json').existsSync(), true);
      expect(
          project
              .file('.github/workflows/copilot-setup-steps.yml')
              .existsSync(),
          true);
      expect(project.file('.project').existsSync(), true);
      expect(project.file('.gitignore').readAsStringSync(),
          '/out\n/.classpath\n/.idea/libraries/\n');
    });

    test('needs a project', () async {
      final empty = await Directory.systemTemp.createTemp('rush-test-empty-');
      addTearDown(() => empty.delete(recursive: true));
      final result = await rush(['agents'], workingDirectory: empty.path);
      expect(result.exitCode, 1, reason: result.output);
      expect(result.output, contains('rush.yml'));
    });
  });

  group('deps sync', () {
    test('writes the VS Code classpath', () async {
      final project = await TestProject.create('vscode_sync_ext');
      project.file('.classpath').deleteSync();
      final result =
          await rush(['deps', 'sync'], workingDirectory: project.dir.path);
      expect(result.exitCode, 0, reason: result.output);
      expect(project.file('.classpath').readAsStringSync(),
          contains('annotations.jar'));
    });

    test('writes the IntelliJ libraries', () async {
      final project = await TestProject.create('intellij_sync_ext');
      Directory('${project.dir.path}/.idea/libraries')
          .deleteSync(recursive: true);
      final result =
          await rush(['deps', 'sync'], workingDirectory: project.dir.path);
      expect(result.exitCode, 0, reason: result.output);
      expect(
          project.file('.idea/libraries/provided-deps.xml').readAsStringSync(),
          contains('annotations.jar'));
      expect(project.file('.idea/libraries/local-deps.xml').existsSync(), true);
      final iml =
          project.file('.idea/intellij-sync-ext.iml').readAsStringSync();
      expect(iml, contains('name="local-deps"'));
      expect(iml, isNot(contains('name="deps"')));
    });

    test('downloads the runtime when RUSH_AI2_RUNTIME_ZIP is empty', () async {
      final home = await Directory.systemTemp.createTemp('rush-home-');
      addTearDown(() => home.delete(recursive: true));
      Directory('${home.path}/libs').createSync();
      final sync = await Process.start(
          rushBin, ['--no-color', 'deps', 'sync', '--dev-deps'],
          workingDirectory: home.path,
          environment: {'RUSH_HOME': home.path, 'RUSH_AI2_RUNTIME_ZIP': ''});
      final output = StringBuffer();
      final downloading = Completer<bool>();
      for (final stream in [sync.stdout, sync.stderr]) {
        stream.transform(utf8.decoder).listen((text) {
          output.write(text);
          if (output.toString().contains('Downloading App Inventor runtime') &&
              !downloading.isCompleted) {
            downloading.complete(true);
          }
        });
      }
      unawaited(sync.exitCode.then((_) {
        if (!downloading.isCompleted) downloading.complete(false);
      }));
      final started = await downloading.future;
      sync.kill();
      await sync.exitCode;
      expect(started, isTrue, reason: output.toString());
    });
  });

  test('clean works on a project that was never built', () async {
    final project = await TestProject.create('unbuilt_ext');
    final result = await rush(['clean'], workingDirectory: project.dir.path);
    expect(result.exitCode, 0, reason: result.output);
  });

  group('migrate', () {
    late Directory project;

    setUp(() async {
      project = await Directory.systemTemp.createTemp('rush-legacy-');
      addTearDown(() => project.delete(recursive: true));
      final files = {
        'rush.yml': '''
name: Legacy
description: Says "hi" for \$5.
homepage: https://example.com/legacy
license: https://example.com/legacy/LICENSE
min_sdk: 21
version:
  number: auto
  name: '1.2.0'
authors:
  - Jane Doe
build:
  desugar:
    enable: true
  kotlin:
    enable: true
assets:
  icon: icon.png
''',
        'src/AndroidManifest.xml': '''
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="com.example.legacy">
    <application></application>
</manifest>
''',
        'src/com/example/legacy/Legacy.kt': r'''
package com.example.legacy

import com.google.appinventor.components.annotations.SimpleFunction
import com.google.appinventor.components.runtime.AndroidNonvisibleComponent
import com.google.appinventor.components.runtime.ComponentContainer

class Legacy(container: ComponentContainer) : AndroidNonvisibleComponent(container.`$form`()) {
    @SimpleFunction(description = "Greets")
    fun Greet(): String = "hi"
}
''',
        'assets/icon.png': 'icon',
      };
      for (final entry in files.entries) {
        File('${project.path}/${entry.key}')
          ..createSync(recursive: true)
          ..writeAsStringSync(entry.value.trimLeft());
      }
      Directory('${project.path}/.rush').createSync();
    });

    test('writes a config the new version builds with', () async {
      final migrated = await rush(['migrate'], workingDirectory: project.path);
      expect(migrated.exitCode, 0, reason: migrated.output);

      final config = File('${project.path}/rush.yml').readAsStringSync();
      expect(
          config,
          allOf(
            contains('homepage: https://example.com/legacy'),
            contains('license: https://example.com/legacy/LICENSE'),
            isNot(contains('desugar')),
            isNot(contains('authors')),
          ));

      final built = await rush(['build'], workingDirectory: project.path);
      expect(built.exitCode, 0, reason: built.output);
    });

    Future<ProcessResult> migrateWithVersionNumber(String number) {
      final config = File('${project.path}/rush.yml');
      config.writeAsStringSync(config.readAsStringSync().replaceFirst(
          RegExp(r'  number: .*\n  name: .*\n'), '  number: $number\n'));
      return rush(['migrate'], workingDirectory: project.path);
    }

    test('uses the version number when there is no version name', () async {
      final migrated = await migrateWithVersionNumber('3');
      expect(migrated.exitCode, 0, reason: migrated.output);
      expect(File('${project.path}/rush.yml').readAsStringSync(),
          contains("version: '3'"));
    });

    test('starts at 1.0.0 when the version number was automatic', () async {
      final migrated = await migrateWithVersionNumber('auto');
      expect(migrated.exitCode, 0, reason: migrated.output);
      expect(migrated.output, contains("version: '1.0.0'"));
      expect(File('${project.path}/rush.yml').readAsStringSync(),
          contains("version: '1.0.0'"));
    });

    test('keeps unlisted local libraries for compilation only', () async {
      final classes = Directory('${project.path}/lib-classes');
      File('${project.path}/Greeting.java').writeAsStringSync(
          'package com.example.lib; public class Greeting { public static String text() { return "hi"; } }');
      final javac = await Process.run(
          'javac', ['-d', classes.path, '${project.path}/Greeting.java']);
      expect(javac.exitCode, 0, reason: '${javac.stderr}');
      final greeting = File('${classes.path}/com/example/lib/Greeting.class');
      File('${project.path}/deps/greeting.jar')
        ..createSync(recursive: true)
        ..writeAsBytesSync(ZipEncoder().encode(Archive()
          ..addFile(ArchiveFile('com/example/lib/Greeting.class',
              greeting.lengthSync(), greeting.readAsBytesSync()))));
      final source = File('${project.path}/src/com/example/legacy/Legacy.kt');
      source.writeAsStringSync(source
          .readAsStringSync()
          .replaceFirst('= "hi"', '= com.example.lib.Greeting.text()'));

      final migrated = await rush(['migrate'], workingDirectory: project.path);
      expect(migrated.exitCode, 0, reason: migrated.output);
      expect(
          File('${project.path}/rush.yml').readAsStringSync(),
          allOf(
              contains('- greeting.jar'),
              contains('libraries:\n  greeting.jar: provided'),
              isNot(contains('provided_dependencies'))));

      final built = await rush(['build'], workingDirectory: project.path);
      expect(built.exitCode, 0, reason: built.output);
    });

    test('moves provided_dependencies of Rush 2 projects to libraries',
        () async {
      final project = await TestProject.create('provided_migrate_ext');
      project.addDependencies(['com.google.code.gson:gson:2.8.9']);
      project.editConfig(
          '#license: LICENSE.txt',
          '# Compile-only libraries.\n'
              'provided_dependencies:\n'
              '- com.google.guava:guava:33.3.1-android\n'
              '- com.google.code.gson:gson:2.8.9');

      final migrated =
          await rush(['migrate'], workingDirectory: project.dir.path);
      expect(migrated.exitCode, 0, reason: migrated.output);
      final config = project.file('rush.yml').readAsStringSync();
      expect(
          config,
          allOf(
              contains('- com.google.code.gson:gson:2.8.9\n'
                  '- com.google.guava:guava:33.3.1-android'),
              contains('libraries:\n'
                  '  com.google.guava:guava: provided\n'
                  '  com.google.code.gson:gson: provided'),
              isNot(contains('provided_dependencies')),
              isNot(contains('Compile-only libraries'))));

      final built = await project.build();
      expect(built.exitCode, 0, reason: built.output);
      expect(built.output, isNot(contains('deprecated')));
    });

    test('removes the repackaging rules Rush applies itself', () async {
      final project = await TestProject.create('old_rules_ext');
      project.editConfig('#license: LICENSE.txt',
          'provided_dependencies:\n- com.google.code.gson:gson:2.8.9');
      final rules = project.file('src/proguard-rules.pro');
      rules.writeAsStringSync('''${rules.readAsStringSync()}
# ProGuard sometimes renames references to these classes.
-keeppackagenames gnu.kawa**, gnu.expr**

# Repackages the optimized classes.
-repackageclasses ${project.package}.repacked
''');

      final migrated =
          await rush(['migrate'], workingDirectory: project.dir.path);
      expect(migrated.exitCode, 0, reason: migrated.output);
      expect(
          rules.readAsStringSync(),
          allOf(
              isNot(contains('-repackageclasses')),
              isNot(contains('-keeppackagenames')),
              isNot(contains('Repackages the optimized classes')),
              contains('-keep @com.google.appinventor')));
      expect(project.file('rush.yml').readAsStringSync(),
          isNot(contains('provided_dependencies')));
      final built = await project.build(['--optimize']);
      expect(built.exitCode, 0, reason: built.output);
    });
  });
}
