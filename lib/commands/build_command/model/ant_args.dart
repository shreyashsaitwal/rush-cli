import 'package:path/path.dart' as p;

/// Generate arguments for the Ant exec.
class AntArgs {
  final String dataDirPath;
  final String cd;
  final String org;
  final String version;
  final String name;

  AntArgs(
    this.dataDirPath,
    this.cd,
    this.org, 
    this.version,
    this.name,
  );

  List toList() {
    final args = <String>[];
    final workspaces = p.join(dataDirPath, 'workspaces');

    // args.add('-q');
    args.add(
        '-buildfile=${p.join(dataDirPath, 'tools', 'apache-ant', 'build.xml')}');

    args.add('-DextSrc=${p.join(cd, 'src')}');
    args.add('-Dclasses=${p.join(workspaces, org, 'classes')}');
    args.add('-DdevDeps=${p.join(cd, 'dependencies', 'dev')}');
    args.add('-Ddeps=${p.join(cd, 'dependencies')}');
    args.add(
        '-DantCon=${p.join(dataDirPath, 'tools', 'ant-contrib-1.0b3.jar')}');

    args.add('-Dextension=$org');
    args.add('-Dout=${p.join(cd, 'out')}');
    args.add('-DrawCls=${p.join(workspaces, org, 'raw-classes')}');
    args.add('-Draw=${p.join(workspaces, org, 'raw')}');
    args.add('-Ddexer=${p.join(dataDirPath, 'tools', 'dx.jar')}');

    args.add('-Droot=$cd');
    args.add('-Dversion=$version');
    args.add('-Dtype=$org.$name');


    return args;
  }
}
