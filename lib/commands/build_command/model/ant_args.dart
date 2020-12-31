import 'package:path/path.dart' as p;

/// Generate arguments for the Ant exec.
class AntArgs {
  final String dataDirPath;
  final String cd;
  final String extType;

  AntArgs(
    this.dataDirPath,
    this.cd,
    this.extType,
  );

  List toList() {
    final args = <String>[];
    final workspaces = p.join(dataDirPath, 'workspaces');

    args.add('-q');
    args.add(
        '-buildfile=${p.join(dataDirPath, 'tools', 'apache-ant', 'build.xml')}');

    args.add('-Dout=${p.join(cd, 'out')}');
    args.add('-Dextension=$extType');
    args.add('-DextSrc=${p.join(workspaces, extType, 'temp')}');

    args.add(
        '-Dclasses=${p.join(workspaces, extType, 'classes')}');
    args.add(
        '-DrawCls=${p.join(workspaces, extType, 'raw-classes')}');
    args.add('-Draw=${p.join(workspaces, extType, 'raw')}');

    args.add('-Dai=${p.join(cd, 'dev-deps')}');
    args.add('-Ddeps=${p.join(cd, 'dependencies')}');

    args.add('-Ddexer=${p.join(dataDirPath, 'tools', 'dx.jar')}');
    args.add(
        '-DantCon=${p.join(dataDirPath, 'tools', 'ant-contrib-1.0b3.jar')}');

    return args;
  }
}
