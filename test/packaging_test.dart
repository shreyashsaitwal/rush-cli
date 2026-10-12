@Timeout(Duration(minutes: 3))
library;

import 'package:test/test.dart';

import 'support/aix.dart';
import 'support/fixtures.dart';
import 'support/project.dart';

void main() {
  group('an AIX rebuilt after files were removed from the project', () {
    late Aix before;
    late Aix after;

    setUpAll(() async {
      final project = await TestProject.create('removed_files_ext');
      project.file('assets/data.json').writeAsStringSync('{}');
      project
          .file('assets/logo.png')
          .writeAsBytesSync(project.file('assets/icon.png').readAsBytesSync());
      project.file('LICENSE.txt').writeAsStringSync('MIT');
      project.editConfig('#assets:', 'assets:\n- data.json\n#assets:');
      project.editConfig('#license: LICENSE.txt', 'license: LICENSE.txt');
      project.editSource('${project.className}.java', 'icon = "icon.png"',
          'icon = "logo.png"');
      final first = await project.build();
      if (first.exitCode != 0) fail(first.output);
      before = project.aix;

      project.file('assets/data.json').deleteSync();
      project.file('assets/logo.png').deleteSync();
      project.file('LICENSE.txt').deleteSync();
      project.editConfig('assets:\n- data.json\n', '');
      project.editConfig('license: LICENSE.txt', '#license: LICENSE.txt');
      project.editSource('${project.className}.java', 'icon = "logo.png"',
          'icon = "icon.png"');
      final second = await project.build();
      if (second.exitCode != 0) fail(second.output);
      after = project.aix;
    });

    test('first shipped the asset, the license and the icon', () {
      expect(before, ships('assets/data.json'));
      expect(before, ships('aiwebres/LICENSE'));
      expect(before, ships('aiwebres/logo.png'));
    });

    test('drops the removed asset', () {
      expect(after.buildInfo['assets'], isEmpty);
      expect(after, isNot(ships('assets/data.json')));
    });

    test('drops the removed license', () {
      expect(after, isNot(ships('aiwebres/LICENSE')));
    });

    test('drops the removed icon', () {
      expect(after, ships('aiwebres/icon.png'));
      expect(after, isNot(ships('aiwebres/logo.png')));
    });
  });

  group('two clean builds of the same project', () {
    late TestProject project;
    late List<int> first;
    late List<int> second;

    setUpAll(() async {
      project = await TestProject.create('reproducible_ext');
      project.addDependencies(['androidx.core:core-ktx:1.5.0']);
      project.file('assets/data.json').writeAsStringSync('{}');
      project.editConfig('#assets:', 'assets:\n- data.json\n#assets:');
      project.file('LICENSE.txt').writeAsStringSync('MIT');
      project.editConfig('#license: LICENSE.txt', 'license: LICENSE.txt');
      project.file('res/values/strings.xml')
        ..createSync(recursive: true)
        ..writeAsStringSync('<resources>\n'
            '    <string name="com_example_reproducibleext_title">Hi</string>\n'
            '</resources>\n');

      Future<List<int>> cleanBuild() async {
        final clean = await rush(['clean'], workingDirectory: project.dir.path);
        if (clean.exitCode != 0) fail(clean.output);
        final build = await project.build();
        if (build.exitCode != 0) fail(build.output);
        return project.aixFile.readAsBytesSync();
      }

      first = await cleanBuild();
      second = await cleanBuild();
    });

    test('produce byte-identical AIX files', () {
      expect(second, first);
    });

    test('ship these entries in this order', () {
      expect(project.aix.entries.toList(), [
        'aars/androidx.core-core-ktx-1.5.0.aar',
        'aars/com.example.reproducibleext.aar',
        'aars/org.jetbrains-annotations-13.0.aar',
        'aars/org.jetbrains.kotlin-kotlin-stdlib-1.4.31.aar',
        'aiwebres/LICENSE',
        'aiwebres/icon.png',
        'assets/data.json',
        'classes.jar',
        'components.json',
        'files/AndroidRuntime.jar',
        'files/component_build_infos.json',
      ]);
    });
  });
}
