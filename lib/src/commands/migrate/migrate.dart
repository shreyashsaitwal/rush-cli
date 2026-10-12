import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:collection/collection.dart';
import 'package:get_it/get_it.dart';
import 'package:path/path.dart' as p;
import 'package:tint/tint.dart';

import 'package:rush/src/commands/deps/sync.dart';
import 'package:rush/src/commands/migrate/old_config/old_config.dart' as old;
import 'package:rush/src/config/config.dart';
import 'package:rush/src/services/file_service.dart';
import 'package:rush/src/services/logger.dart';
import 'package:rush/src/utils/constants.dart';

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
      desugar: oldConfig.build?.desugar?.enable ?? false,
      dependencies: dependencies,
      providedDependencies: compileOnlyDependencies,
      license: oldConfig.license ?? '',
      homepage: oldConfig.homepage ?? '',
      authors: oldConfig.authors ?? [],
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

    if (config.authors.isNotEmpty) {
      contents += '''
# Authors of your extension.
authors:
${config.authors.map((el) => '- $el').join('\n')}

''';
    }

    if (config.desugar) {
      contents += '''
# Desugars Java 8+ language features so that they work on older Android versions.
desugar: true

''';
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

    if (config.providedDependencies.isNotEmpty) {
      contents += '''
# Similar to dependencies, except libraries defined as provided are not included
# in the final AIX.
provided_dependencies:
${config.providedDependencies.map((el) => '- $el').join('\n')}

''';
    }

    _fs.configFile.writeAsStringSync(contents);
  }
}
