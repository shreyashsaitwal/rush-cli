import 'package:path/path.dart' as p;

class FileService {
  final String cwd;
  final String dataDir;

  FileService(this.cwd, this.dataDir);

  String get srcDir => p.join(cwd, 'src');
  String get workspacesDir => p.join(dataDir, 'workspaces');
  String get toolsDir => p.join(dataDir, 'tools');
  String get devDepsDir => p.join(dataDir, 'dev-deps');
}
