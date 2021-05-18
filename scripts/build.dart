import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as p;

void main(List<String> args) {
  final parser = ArgParser()..addOption('token', abbr: 't');
  final res = parser.parse(args);

  final gh_pat = res['token'];

  final cd = Directory.current.path;
  final envDart = File(p.join(cd, 'lib', 'installer', 'env.dart'));

  envDart.writeAsStringSync('const GH_PAT = \'$gh_pat\';');

  final rushExe = Process.runSync('dart', [
    'compile',
    'exe',
    '-o',
    p.join(cd, 'build', 'bin', 'rush' + (Platform.isWindows ? '.exe' : '')),
    p.join(cd, 'bin', 'rush.dart')
  ]);

  print(rushExe.stdout.toString().trim());
  print(rushExe.stderr.toString().trim());

  var rushInit = Process.runSync('dart', [
    'compile',
    'exe',
    '-o',
    p.join(cd, 'build', 'bin', 'rush-init-${_getOsString()}'),
    p.join(cd, 'bin', 'rush-init.dart')
  ]);

  print(rushInit.stdout.toString().trim());
  print(rushInit.stderr.toString().trim());
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
