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

  Process.run('dart', [
    'compile',
    'exe',
    '-o',
    'build/bin/rush-init-$_getOsString()',
    'bin/rush-init.dart'
  ]).asStream().asBroadcastStream().listen((event) {
    print(event.stdout);
  });
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
