import 'dart:io' show Directory, File, Platform, exit;

import 'package:hive/hive.dart';
import 'package:path/path.dart' as p;
import 'package:dart_casing/dart_casing.dart';
import 'package:rush_cli/commands/new_command/questions.dart';
import 'package:rush_cli/mixins/copy_mixin.dart';
import 'package:rush_cli/templates/android_manifest.dart';
import 'package:rush_cli/templates/dot_gitignore.dart';
import 'package:rush_cli/templates/readme.dart';

import 'package:rush_prompt/rush_prompt.dart';
import 'package:rush_cli/templates/rush_yaml_template.dart';
import 'package:rush_cli/templates/extension_template.dart';

class NewCommand with CopyMixin {
  final String _cd;

  NewCommand(this._cd);

  /// Creates a new extension project in the current directory.
  Future<void> run() async {
    final answers = RushPrompt(questions: Questions.questions).askAll();
    final name = answers[0][1].toString().trim();
    final orgName = answers[1][1].toString().trim();
    final authorName = answers[2][1].toString().trim();
    final versionName = answers[3][1].toString().trim();

    final isOrgAndNameSame = orgName.split('.').last == Casing.camelCase(name);
    var package;
    if (isOrgAndNameSame) {
      package = orgName;
    } else {
      package = orgName + '.' + Casing.camelCase(name);
    }

    final extPath =
        p.joinAll([_cd, Casing.camelCase(name), 'src', ...package.split('.')]);

    // Creates the required files for the extension.
    try {
      _writeFile(
          p.join(extPath, '${Casing.pascalCase(name)}.java'),
          getExtensionTemp(
            Casing.pascalCase(name),
            package,
          ));

      _writeFile(p.join(_cd, Casing.camelCase(name), 'rush.yml'),
          getRushYaml(name, versionName, authorName));

      _writeFile(
          p.join(_cd, Casing.camelCase(name), '.gitignore'), getDotGitignore());

      _writeFile(
          p.join(_cd, Casing.camelCase(name), 'README.md'), getReadme(name));

      _writeFile(
          p.join(_cd, Casing.camelCase(name), 'src', 'AndroidManifest.xml'),
          getManifestXml(orgName));

      _writeFile(
          p.join(_cd, Casing.camelCase(name), 'deps', '.placeholder'), '');
    } catch (e) {
      ThrowError(message: 'ERR ' + e.toString());
    }

    try {
      Directory(p.join(_cd, Casing.camelCase(name), '.rush', 'dev_deps'))
          .createSync(recursive: true);

      Directory(p.join(_cd, Casing.camelCase(name), 'assets'))
          .createSync(recursive: true);

      Directory(p.join(_cd, Casing.camelCase(name), '.rush'))
          .createSync(recursive: true);
    } catch (e) {
      ThrowError(message: 'ERR ' + e.toString());
    }

    Hive.init(p.join(_cd, Casing.camelCase(name), '.rush'));
    var box = await Hive.openBox('data');
    await box.putAll({
      'version': 1,
      'org': package,
      'rushYmlLastMod': DateTime.now(),
      'srcDirLastMod': DateTime.now(),
    });

    // Copy dev-deps.
    final baseDir = Platform.script.toFilePath(windows: Platform.isWindows);
    final devDepsDir = p.join(baseDir.split('bin').first, 'dev-deps');
    copyDir(Directory(devDepsDir),
        Directory(p.join(_cd, Casing.camelCase(name), '.rush', 'dev_deps')));

    exit(0);
  }

  void _writeFile(String path, String content) {
    File(path)
      ..createSync(recursive: true)
      ..writeAsStringSync(content);
  }
}
