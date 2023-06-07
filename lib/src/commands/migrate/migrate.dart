import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:collection/collection.dart';
import 'package:get_it/get_it.dart';
import 'package:path/path.dart' as p;
import 'package:tint/tint.dart';

import 'package:rush_cli/src/commands/deps/sync.dart';
import 'package:rush_cli/src/commands/migrate/old_config/old_config.dart'
    as old;
import 'package:rush_cli/src/config/config.dart';
import 'package:rush_cli/src/services/file_service.dart';
import 'package:rush_cli/src/services/logger.dart';
import 'package:rush_cli/src/utils/constants.dart';

class MigrateCommand extends Command<int> {
  final _fs = GetIt.I<FileService>();
  final _lgr = GetIt.I<Logger>();

  @override
  String get description =>
      'Migrates extension projects built with Rush v1 to Rush v2';

  @override
  String get name => 'migrate';

  @override
  Future<int> run() async {
    _lgr.startTask('Initializing');
    final oldConfig = await old.OldConfig.load(_fs.configFile, _lgr);
    if (oldConfig == null) {
      _lgr
        ..err('Failed to load old config')
        ..stopTask(false);
      return 1;
    }

    final comptimeDeps = _fs.localDepsDir
        .listSync()
        .map((el) => p.basename(el.path))
        .where((el) => !(oldConfig.deps?.contains(el) ?? true));

    final newConfig = Config(
      version: oldConfig.version.name.toString(),
      minSdk: oldConfig.minSdk ?? 7,
      assets: oldConfig.assets.other ?? [],
      desugar: oldConfig.build?.desugar?.enable ?? false,
      runtimeDeps: oldConfig.deps ?? [],
      comptimeDeps: comptimeDeps.toList(),
      license: oldConfig.license ?? '',
      homepage: oldConfig.homepage ?? '',
      kotlin: Kotlin(
        compilerVersion: defaultKtVersion,
      ),
    );
    _lgr.stopTask();

    _lgr.startTask('Parsing old source files');
    final srcFile = _fs.srcDir
        .listSync(recursive: true)
        .whereType<File>()
        .firstWhereOrNull(
            (el) => p.basenameWithoutExtension(el.path) == oldConfig.name);
    if (srcFile == null) {
      _lgr
        ..err('Unable to find the main extension source file.')
        ..log(
            '${'help  '.green()} Make sure that the name of the main source file matches with `name` field in rush.yml: `${oldConfig.name}`');
      return 1;
    }

    _lgr.info('Main extension source file found: ${srcFile.path}');
    _editSourceFile(srcFile, oldConfig);
    _lgr.stopTask();

    _lgr.startTask('Updating config file (rush.yml)');
    _updateConfig(newConfig, oldConfig.build?.kotlin?.enable ?? false);
    _deleteOldHiveBoxes();
    _lgr.stopTask();

    // No need to start a task here since the sync command does that on its own.
    await SyncSubCommand().run(title: 'Syncing dependencies');
    return 0;
  }

  void _editSourceFile(File srcFile, old.OldConfig oldConfig) {
    final RegExp regex;
    if (p.extension(srcFile.path) == '.java') {
      regex = RegExp(r'.*class.+\s+extends\s+AndroidNonvisibleComponent.*');
    } else {
      regex = RegExp(
          r'.*class\s+.+\s*\((.|\n)*\)\s+:\s+AndroidNonvisibleComponent.*');
    }

    final fileContent = srcFile.readAsStringSync();
    final match = regex.firstMatch(fileContent);
    final matchedStr = match?.group(0);

    if (match == null || matchedStr == null) {
      _lgr
        ..err('Unable to process src file: ${srcFile.path}')
        ..log('Are you sure that it is a valid extension source file?',
            'help  '.green());
      throw Exception();
    }

    final description = oldConfig.description.isNotEmpty
        ? oldConfig.description
        : 'Extension component for ${oldConfig.name}. Built with <3 and Rush.';
    final annotation = '''
// FIXME: You might want to shorten this by importing `@Extension` annotation.
@com.google.appinventor.components.annotations.Extension(
    description = "$description",
    icon = "${oldConfig.assets.icon}"
)
''';

    final newContent =
        fileContent.replaceFirst(matchedStr, annotation + matchedStr);
    srcFile.writeAsStringSync(newContent);
  }

  void _deleteOldHiveBoxes() {
    _fs.dotRushDir
        .listSync()
        .where((el) =>
            p.extension(el.path) == '.hive' || p.extension(el.path) == '.lock')
        .forEach((el) {
      el.deleteSync();
    });
  }

  void _updateConfig(Config config, bool enableKotlin) {
    var contents = '''
# This is the version name of your extension. You should update it everytime you
# publish a new version of your extension.
version: '${config.version}'

# The minimum Android SDK level your extension supports. Minimum SDK defined in
# AndroidManifest.xml is ignored, you should always define it here.
min_sdk: ${config.minSdk}

''';

    if (config.homepage.isNotEmpty) {
      contents += '''
# Homepage of your extension. This may be the announcement thread on community 
# forums or a link to your GitHub repository.
${config.homepage}\n\n''';
    }

    if (config.license.isNotEmpty) {
      contents += '''
# Path to the license file of your extension. This should be a path to a local file
# or link to something hosted online.
${config.license}\n\n''';
    }

    if (config.assets.isNotEmpty) {
      contents += '''
# Assets that your extension needs. Every asset file must be stored in the assets
# directory as well as declared here. Assets can be of any type.
assets:
${config.assets.map((el) => '- $el').join('\n')}

''';
    }

    if (config.desugar) {
      contents += '''
# Desuagring allows you to use Java 8 language features in your extension. You 
# also need to enable desugaring if any of your dependencies use Java 8 language
# features.
desugar: true\n\n''';
    }

    if (enableKotlin) {
      contents += '''
# Kotlin specific configuration.
kotlin:
  compiler_version: '${config.kotlin.compilerVersion}'

''';
    }

    if (config.runtimeDeps.isNotEmpty || enableKotlin) {
      contents += '''
# External libraries your extension depends on. These can be local JARs / AARs
# stored in the "deps" directory or coordinates of remote Maven artifacts in
# <groupId>:<artifactId>:<version> format. 
dependencies:
${enableKotlin ? 'org.jetbrains.kotlin:kotlin-stdlib:${config.kotlin.compilerVersion}\n' : ''}${config.runtimeDeps.map((el) {
  if (el != '.placeholder') return '- $el';
}).join('\n')}

''';
    }

    if (config.comptimeDeps.isNotEmpty) {
      contents += '''
# Similar to dependencies, except libraries defined as comptime (compile-time)
# are only available during compilation and not included in the resulting AIX.
comptime_dependencies:
${config.comptimeDeps.map((el) {
  if (el != '.placeholder') return '- $el';
}).join('\n')}
''';
    }

    _fs.configFile.writeAsStringSync(contents);
  }
}
