import 'dart:async';
import 'dart:io' show Directory, File, Process, exit;

import 'package:path/path.dart' as path;
import 'package:archive/archive.dart';
import 'package:dart_casing/dart_casing.dart';
import 'package:dart_console/dart_console.dart';

import 'package:rush_prompt/rush_prompt.dart';
import 'package:rush_cli/templates/rush_yaml_template.dart';
import 'package:rush_cli/templates/extension_template.dart';
import 'package:rush_cli/templates/dot_classpath_template.dart';
import 'package:rush_cli/commands/new_command/mixins/app_data_dir_mixin.dart';
import 'package:rush_cli/commands/new_command/mixins/download_mixin.dart';
import 'package:rush_cli/commands/new_command/mixins/new_cmd_ques_mixin.dart';

class NewCommand with DownloadMixin, AppDataMixin, QuestionsMixin {
  NewCommand(this._currentDir);

  final String _currentDir;
  final _compileDepsDirPath =
      path.join(AppDataMixin.dataStorageDir(), 'compile_deps');

  Future<void> run() async {
    final rushDataDir = Directory(_compileDepsDirPath);

    if (!rushDataDir.existsSync() || rushDataDir.listSync().isEmpty) {
      Console()
        ..writeLine(
            'Rush needs to download following set of files to function properly.')
        ..setForegroundColor(ConsoleColor.cyan)
        // ..writeLine('• Apache Ant (??.? M)')
        ..writeLine('• Android Support libraries (33.5 M)')
        ..resetColorAttributes()
        ..writeLine(
            'This is a one-time process and you won\'t be asked to download the above files again (unless there is a crucial update in one or more of them).');

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

    final extName = answers[0][1].toString().trim();
    final orgName = answers[1][1].toString().trim();
    final authorName = answers[2][1].toString().trim();
    final versionName = answers[3][1].toString().trim();

    final extPath = path.joinAll([
      _currentDir,
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

      File(path.join(_currentDir, 'rush.yaml'))
        ..createSync(recursive: true)
        ..writeAsStringSync(
          getRushYml(extName, versionName, authorName),
        );

      File(path.join(_currentDir, '.classpath'))
        ..createSync(recursive: true)
        ..writeAsStringSync(
          getDotClasspath(path.join(AppDataMixin.dataStorageDir(), 'compile_deps')),
        );
    } catch (e) {
      ThrowError(message: e);
    }
  }

  void _downloadDepsArchive() async {
    final progress = ProgressBar('Downloading dependencies...');
    const url =
        'https://firebasestorage.googleapis.com/v0/b/rush-cli.appspot.com/o/compile_deps.zip?alt=media&token=63834a4c-e78f-4217-8720-4d1dc3fb7ae6';

    await download(progress, url, _compileDepsDirPath);
  }

  void _extractDeps() {
    final depsFile = File(path.join(_compileDepsDirPath, 'compile_deps.zip'));
    if (!depsFile.existsSync()) {
      ThrowError(message: 'Unable to extract dependencies. Aborting...');
    }

    final bytes = depsFile.readAsBytesSync();
    final zip = ZipDecoder().decodeBytes(bytes).files;
    final total = zip.length;

    final progress = ProgressBar('Extracting dependencies...');
    progress.totalProgress = total;

    for (var i = 0; i < zip.length; i++) {
      progress.update(i + 1);
      if (zip[i].isFile) {
        final data = zip[i].content;
        try {
          File(path.join(_compileDepsDirPath, zip[i].name))
            ..createSync(recursive: true)
            ..writeAsBytesSync(data);
        } catch (e) {
          ThrowError(message: e);
        }
      }
    }

    depsFile.deleteSync();
  }
}
