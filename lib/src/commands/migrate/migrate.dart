import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:collection/collection.dart';
import 'package:get_it/get_it.dart';
import 'package:path/path.dart' as p;
import 'package:tint/tint.dart';
import 'package:yaml_edit/yaml_edit.dart';

import 'package:rush/src/commands/deps/sync.dart';
import 'package:rush/src/commands/migrate/old_config/old_config.dart' as old;
import 'package:rush/src/commands/migrate/provided_dependencies.dart';
import 'package:rush/src/commands/migrate/rush_rules.dart';
import 'package:rush/src/config/config.dart';
import 'package:rush/src/config/library_placement.dart';
import 'package:rush/src/services/file_service.dart';
import 'package:rush/src/services/logger.dart';
import 'package:rush/src/utils/constants.dart';
import 'package:rush/src/utils/file_extension.dart';

class MigrateCommand extends Command<int> {
  final _fs = GetIt.I<FileService>();
  final _lgr = GetIt.I<Logger>();

  @override
  String get description =>
      'Migrates extension projects built with Rush v1 to Rush v2, and moves '
      'provided_dependencies to libraries';

  @override
  String get name => 'migrate';

  @override
  Future<int> run() async {
    if (!_isRush1Project()) {
      return _updateRush2Project();
    }
    _lgr.startTask('Initializing');
    final oldConfig = await old.OldConfig.load(_fs.configFile, _lgr);
    if (oldConfig == null) {
      _lgr
        ..err('Failed to load old config')
        ..stopTask(false);
      return 1;
    }

    final dependencies = oldConfig.deps ?? [];
    final compileOnlyDependencies = await _fs.localDepsDir.exists()
        ? _fs.localDepsDir
            .listSync()
            .map((el) => p.basename(el.path))
            .where((el) => el.endsWith('.jar') || el.endsWith('.aar'))
            .whereNot(dependencies.contains)
            .sorted()
        : <String>[];

    final newConfig = Config(
      version: _versionName(oldConfig.version),
      minSdk: oldConfig.minSdk ?? 7,
      assets: oldConfig.assets.other ?? [],
      dependencies: [...dependencies, ...compileOnlyDependencies],
      libraries: {
        for (final dependency in compileOnlyDependencies)
          dependency: LibraryPlacement.provided,
      },
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
    if (!_editSourceFile(srcFile, oldConfig)) {
      _lgr.stopTask(false);
      return 1;
    }
    _lgr.stopTask();

    _lgr.startTask('Updating config file (rush.yml)');
    _updateConfig(newConfig, oldConfig.build?.kotlin?.enable ?? false);
    await _removeRushRules();
    _deleteOldHiveBoxes();
    _lgr.stopTask();

    // No need to start a task here since the sync command does that on its own.
    return SyncSubCommand().run(title: 'Syncing dependencies');
  }

  String _versionName(old.Version version) {
    if (version.name != null) {
      return version.name.toString();
    }
    if (version.number is int) {
      return version.number.toString();
    }
    _lgr.warn(
        'The old rush.yml has no version name, so the migrated one starts '
        "at version: '1.0.0'");
    return '1.0.0';
  }

  bool _editSourceFile(File srcFile, old.OldConfig oldConfig) {
    final isJava = p.extension(srcFile.path) == '.java';
    final RegExp regex;
    if (isJava) {
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
      return false;
    }

    final description = _stringLiteral(
        oldConfig.description.isNotEmpty
            ? oldConfig.description
            : 'Extension component for ${oldConfig.name}. Built with <3 and Rush.',
        escapeDollar: !isJava);
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
    return true;
  }

  String _stringLiteral(String text, {required bool escapeDollar}) {
    final escaped = text.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
    return escapeDollar ? escaped.replaceAll(r'$', r'\$') : escaped;
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

  bool _isRush1Project() =>
      (YamlEditor(_fs.configFile.readAsStringSync()).parseAt([]).value as Map)
          .containsKey('name');

  Future<int> _updateRush2Project() async {
    _lgr.startTask('Updating rush.yml and src/proguard-rules.pro');
    final config = await Config.load(_fs.configFile, _lgr);
    if (config == null) {
      _lgr.stopTask(false);
      return 1;
    }
    final movedDependencies = config.providedDependencies.isNotEmpty;
    if (movedDependencies) {
      await _fs.configFile.writeAsString(withProvidedDependenciesAsLibraries(
          await _fs.configFile.readAsString()));
    }
    final removedRules = await _removeRushRules();
    if (!movedDependencies && !removedRules) {
      _lgr.info('Nothing to migrate');
    }
    _lgr.stopTask();
    return 0;
  }

  Future<bool> _removeRushRules() async {
    final rules = p.join(_fs.srcDir.path, 'proguard-rules.pro').asFile();
    if (!await rules.exists()) {
      return false;
    }
    final contents = await rules.readAsString();
    final cleaned = withoutRushRules(contents);
    if (cleaned == contents) {
      return false;
    }
    await rules.writeAsString(cleaned);
    return true;
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
homepage: ${config.homepage}\n\n''';
    }

    if (config.license.isNotEmpty) {
      contents += '''
# Path to the license file of your extension. This should be a path to a local file
# or link to something hosted online.
license: ${config.license}\n\n''';
    }

    if (config.assets.isNotEmpty) {
      contents += '''
# Assets that your extension needs. Every asset file must be stored in the assets
# directory as well as declared here. Assets can be of any type.
assets:
${config.assets.map((el) => '- $el').join('\n')}

''';
    }

    if (enableKotlin) {
      contents += '''
# Kotlin specific configuration.
kotlin:
  compiler_version: '${config.kotlin.compilerVersion}'

''';
    }

    final dependencies = [
      if (enableKotlin)
        'org.jetbrains.kotlin:kotlin-stdlib:${config.kotlin.compilerVersion}',
      ...config.dependencies.whereNot((el) => el == '.placeholder'),
    ];
    if (dependencies.isNotEmpty) {
      contents += '''
# External libraries your extension depends on. These can be local JARs / AARs
# stored in the "deps" directory or coordinates of remote Maven artifacts in
# <groupId>:<artifactId>:<version> format. 
dependencies:
${dependencies.map((el) => '- $el').join('\n')}

''';
    }

    if (config.libraries.isNotEmpty) {
      contents += '''
# Where a library from dependencies goes, when Rush's choice doesn't fit.
libraries:
${config.libraries.entries.map((el) => '  ${el.key}: ${el.value.name}').join('\n')}

''';
    }

    _fs.configFile.writeAsStringSync(contents);
  }
}
