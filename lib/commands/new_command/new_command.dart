import 'dart:io' show Directory, File, exit;

import 'package:path/path.dart' as path;
import 'package:archive/archive.dart';
import 'package:dart_casing/dart_casing.dart';
import 'package:dart_console/dart_console.dart';

import 'package:rush_prompt/rush_prompt.dart';
import 'package:rush_cli/templates/rush_yaml_template.dart';
import 'package:rush_cli/templates/extension_template.dart';
import 'package:rush_cli/commands/new_command/mixins/app_data_dir_mixin.dart';
import 'package:rush_cli/commands/new_command/mixins/download_mixin.dart';
import 'package:rush_cli/commands/new_command/mixins/new_cmd_ques_mixin.dart';

class NewCommand with DownloadMixin, AppDataMixin, QuestionsMixin {
  NewCommand(this._currentDir);

  final String _currentDir;
  final _compileDepsDirPath =
      path.join(AppDataMixin.dataStorageDir(), 'compile-deps');

  Future<void> run() async {
    final rushDataDir = Directory(AppDataMixin.dataStorageDir());

    if (!rushDataDir.existsSync() || rushDataDir.listSync().isEmpty) {
      Console().writeLine('''
Rush needs to download some Java dependencies and other packages (total download size: 43.3 MB) to compile your extension(s).
This is a one-time process, and you won\'t need to download these files again (unless there is a necessary update in one or more of them).''');

      final continueProcess =
          BoolQuestion(id: 'continue', question: 'Do you want to continue?')
              .ask()[1];

      if (!continueProcess) {
        exit(0);
      }

      try {
        rushDataDir.createSync(recursive: true);
      } catch (e) {
        ThrowError(message: e);
      }

      await _downloadDepsArchive();
      await _extractDeps();
    }

    final answers = RushPrompt(questions: newCmdQues).askAll();

    final extName = Casing.pascalCase(answers[0][1].toString());
    final orgName = answers[1][1].toString().trim();
    final authorName = answers[2][1].toString().trim();
    final versionName = answers[3][1].toString().trim();

    final extPath = path.joinAll([
      _currentDir,
      Casing.camelCase(extName),
      'src',
      ...orgName.split('.'),
      Casing.camelCase(extName),
    ]);

    try {
      File(path.join(extPath, '$extName.java'))
        ..createSync(recursive: true)
        ..writeAsStringSync(
          getExtensionTemp(
            Casing.pascalCase(extName),
            orgName + '.' + Casing.camelCase(extName),
          ),
        );

      File(path.join(_currentDir, Casing.camelCase(extName), 'rush.yaml'))
        ..createSync(recursive: true)
        ..writeAsStringSync(
          getRushYml(extName, versionName, authorName),
        );

      Directory(path.join(
              _currentDir, Casing.camelCase(extName), 'dependencies'))
          .createSync();
    } catch (e) {
      ThrowError(message: e);
    }

    _copyAll(_compileDepsDirPath,
        path.join(_currentDir, Casing.camelCase(extName), 'dependencies'));
  }

  void _downloadDepsArchive() async {
    final progress = ProgressBar('Downloading packages...');
    const url =
        'https://firebasestorage.googleapis.com/v0/b/rush-cli.appspot.com/o/packages.zip?alt=media&token=472bae35-ac1a-422c-affe-1c81ba223931';

    await download(progress, url, AppDataMixin.dataStorageDir());
  }

  void _extractDeps() {
    final packageZip = File(path.join(AppDataMixin.dataStorageDir(), 'packages.zip'));
    if (!packageZip.existsSync()) {
      ThrowError(message: 'Unable to extract packages. Aborting...');
    }

    final bytes = packageZip.readAsBytesSync();
    final zip = ZipDecoder().decodeBytes(bytes).files;
    final total = zip.length;

    final progress = ProgressBar('Extracting packages...');
    progress.totalProgress = total;

    for (var i = 0; i < zip.length; i++) {
      progress.update(i + 1);
      if (zip[i].isFile) {
        final data = zip[i].content;
        try {
          File(path.join(AppDataMixin.dataStorageDir(), zip[i].name))
            ..createSync(recursive: true)
            ..writeAsBytesSync(data);
        } catch (e) {
          ThrowError(message: e);
        }
      }
    }

    packageZip.deleteSync();
  }

  void _copyAll(String depsDir, String copyTo) {
    final deps = Directory(depsDir).listSync();

    deps.forEach((file) {
      final name = file.path.split('/').last;

      if (name.endsWith('.jar') || name.endsWith('.aar') || name.endsWith('.so')) {
        File(file.path).copySync(path.join(copyTo, name));
      } else {
        _copyAll(file.path, path.join(copyTo, name));
      }
    });
  }
}
