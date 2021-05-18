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

  final process = Process.runSync('dart', [
    'compile',
    'exe',
    '-o',
    p.join(cd, 'build', 'bin', 'rush-init-${_getOsString()}'),
    p.join(cd, 'bin', 'rush-init.dart')
  ]);

  print(process.stdout ?? '');
  print(process.stderr ?? '');

  envDart.deleteSync();
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
