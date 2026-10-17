import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'aix.dart';

final String rushBin = Platform.environment['RUSH_TEST_BIN'] ??
    (throw StateError('Run the tests with tool/test.sh'));

Future<ProcessResult> rush(List<String> args,
        {required String workingDirectory, Map<String, String>? environment}) =>
    Process.run(rushBin, ['--no-color', ...args],
        workingDirectory: workingDirectory, environment: environment);

extension ProcessOutput on ProcessResult {
  String get output => '${this.stdout}${this.stderr}';
}

class TestProject {
  TestProject._(this.dir, this.package, this.className);

  final Directory dir;
  final String package;
  final String className;

  static Future<TestProject> create(
    String name, {
    String language = 'java',
    String parentPrefix = 'rush-test-',
  }) async {
    final parent = await Directory.systemTemp.createTemp(parentPrefix);
    addTearDown(() => parent.delete(recursive: true));
    final result = await rush(
      [
        'create',
        name,
        '-p',
        'com.example',
        '-l',
        language,
        '--ide',
        'intellij'
      ],
      workingDirectory: parent.path,
    );
    if (result.exitCode != 0 ||
        !Directory(p.join(parent.path, name)).existsSync()) {
      throw StateError('rush create failed:\n${result.output}');
    }
    final simpleName =
        name.split('_').map((w) => w[0].toUpperCase() + w.substring(1)).join();
    return TestProject._(
      Directory(p.join(parent.path, name)),
      'com.example.${simpleName.toLowerCase()}',
      simpleName,
    );
  }

  File file(String relativePath) => File(p.join(dir.path, relativePath));

  File source(String relativePath) =>
      file(p.join('src', p.joinAll(package.split('.')), relativePath));

  void addDependencies(List<String> coordinates) {
    final config = file('rush.yml');
    config.writeAsStringSync(config.readAsStringSync().replaceFirst(
        RegExp(r'^#?dependencies:$', multiLine: true),
        ['dependencies:', for (final c in coordinates) '- $c'].join('\n')));
  }

  void placeLibraries(Map<String, String> placements) =>
      file('rush.yml').writeAsStringSync(
          [
            '',
            'libraries:',
            for (final MapEntry(key: library, value: placement)
                in placements.entries)
              '  $library: $placement',
            '',
          ].join('\n'),
          mode: FileMode.append);

  void keepOriginalNames(List<String> packages) =>
      file('rush.yml').writeAsStringSync(
          [
            '',
            'original_names:',
            for (final package in packages) '- $package',
            ''
          ].join('\n'),
          mode: FileMode.append);

  Future<ProcessResult> depsTree() =>
      rush(['deps', 'tree'], workingDirectory: dir.path);

  void setMinSdk(int minSdk) {
    final config = file('rush.yml');
    config.writeAsStringSync(config.readAsStringSync().replaceFirst(
        RegExp(r'^min_sdk: \d+$', multiLine: true), 'min_sdk: $minSdk'));
  }

  Future<ProcessResult> build(
          [List<String> args = const [], Map<String, String>? environment]) =>
      rush(['build', ...args],
          workingDirectory: dir.path, environment: environment);

  File get aixFile => Directory(p.join(dir.path, 'out'))
      .listSync()
      .whereType<File>()
      .singleWhere((f) => f.path.endsWith('.aix'));

  Aix get aix => Aix(aixFile, package);

  String get packagePath => package.replaceAll('.', '/');

  String classFile(String name) => '$packagePath/$name.class';
}
