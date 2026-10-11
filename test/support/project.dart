import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

final String rushBin = Platform.environment['RUSH_TEST_BIN'] ??
    (throw StateError('Run the tests with tool/test.sh'));

Future<ProcessResult> rush(List<String> args,
        {required String workingDirectory}) =>
    Process.run(rushBin, ['--no-color', ...args],
        workingDirectory: workingDirectory);

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
    String language = 'kotlin',
    String parentPrefix = 'rush-test-',
  }) async {
    final parent = await Directory.systemTemp.createTemp(parentPrefix);
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

  void setMinSdk(int minSdk) {
    final config = file('rush.yml');
    config.writeAsStringSync(config.readAsStringSync().replaceFirst(
        RegExp(r'^min_sdk: \d+$', multiLine: true), 'min_sdk: $minSdk'));
  }

  Future<ProcessResult> build([List<String> args = const []]) =>
      rush(['build', ...args], workingDirectory: dir.path);

  Archive get aix {
    final out = Directory(p.join(dir.path, 'out'));
    final aixFile = out
        .listSync()
        .whereType<File>()
        .singleWhere((f) => f.path.endsWith('.aix'));
    return ZipDecoder().decodeBytes(aixFile.readAsBytesSync());
  }

  Set<String> get runtimeClasses {
    final jar = aix.files
        .singleWhere((f) => f.name.endsWith('files/AndroidRuntime.jar'));
    return ZipDecoder()
        .decodeBytes(jar.content)
        .files
        .map((f) => f.name)
        .toSet();
  }

  Archive bundledAar(String fileName) => ZipDecoder().decodeBytes(
      aix.files.singleWhere((f) => f.name.endsWith('/aars/$fileName')).content);

  Map<String, dynamic> get buildInfo {
    final json = aix.files.singleWhere(
        (f) => f.name.endsWith('files/component_build_infos.json'));
    return (jsonDecode(utf8.decode(json.content)) as List).single
        as Map<String, dynamic>;
  }

  List<String> get libraries => buildInfo['libraries'].cast<String>();

  List<Map<String, dynamic>> get components {
    final json =
        aix.files.singleWhere((f) => f.name.endsWith('/components.json'));
    return (jsonDecode(utf8.decode(json.content)) as List)
        .cast<Map<String, dynamic>>();
  }

  String get packagePath => package.replaceAll('.', '/');

  String classFile(String name) => '$packagePath/$name.class';

  Future<void> delete() => dir.parent.delete(recursive: true);
}
