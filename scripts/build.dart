import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as p;
import 'package:process_runner/process_runner.dart';

void main(List<String> args) {
  final parser = ArgParser()
    ..addOption('token', abbr: 't')
    ..addOption('version', abbr: 'v');
  final res = parser.parse(args);

  final gh_pat = res['token'];
  final version = res['version'];

  final cd = Directory.current.path;

  final versionDart = File(p.join(cd, 'lib', 'version.dart'));
  versionDart.writeAsStringSync('''
// Auto-generated. Do not modify.
const String rushVersion = \'$version\';
const String rushBuiltOn = \'${DateTime.now().toUtc()}\';
''');

  final envDart = File(p.join(cd, 'lib', 'env.dart'));

  envDart.writeAsStringSync(
      '// Auto-generated. Do not modify.\nconst GH_PAT = \'$gh_pat\';');

  ProcessRunner().runProcess([
    'dart',
    'compile',
    'exe',
    '-o',
    p.join(cd, 'build', 'bin', 'rush' + (Platform.isWindows ? '.exe' : '')),
    p.join(cd, 'bin', 'rush.dart')
  ], printOutput: true);

  if (Platform.isWindows) {
    ProcessRunner().runProcess([
      'dart',
      'compile',
      'exe',
      '-o',
      p.join(cd, 'build', 'bin', 'swap.exe'),
      p.join(cd, 'bin', 'swap.dart')
    ], printOutput: true);
  }

  ProcessRunner().runProcess([
    'dart',
    'compile',
    'exe',
    '-o',
    p.join(cd, 'build', 'bin', 'rush-init-${_getOsString()}'),
    p.join(cd, 'bin', 'rush-init.dart')
  ], printOutput: true);
}

String _getOsString() {
  final os = Platform.operatingSystem;

  switch (os.toLowerCase()) {
    case 'windows':
      return 'win.exe';

    case 'macos':
      return 'mac';

    default:
      return 'linux';
  }
}
