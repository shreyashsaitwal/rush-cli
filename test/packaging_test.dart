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
}
