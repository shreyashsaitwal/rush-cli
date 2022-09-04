import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:get_it/get_it.dart';
import 'package:github/github.dart';
import 'package:collection/collection.dart';
import 'package:http/http.dart';
import 'package:path/path.dart' as p;

import '../../utils/file_extension.dart';
import '../../services/file_service.dart';
import '../rush_command.dart';
import 'models/asset_info.dart';

class Upgrade extends RushCommand {
  final _fs = GetIt.I<FileService>();

  Upgrade() {
    argParser
      ..addFlag('force',
          abbr: 'f',
          help: 'Upgrades Rush even if you\'re using the latest version.')
      ..addOption('access-token',
          abbr: 't',
          help:
              'Your GitHub access token. Normally, you don\'t need to worry about this.');
  }

  @override
  String get description => 'Upgrades Rush to the latest available version.';

  @override
  String get name => 'upgrade';

  @override
  Future<void> run() async {
    final gh = GitHub(
        auth: Authentication.withToken(argResults!['access-token'] as String?));
    final release = await gh.repositories
        .getLatestRelease(RepositorySlug.full('shreyashsaitwal/rush-cli'));

    final assetInfoJsonUrl = release.assets
        ?.singleWhereOrNull((el) => el.name == 'asset-info.json')
        ?.browserDownloadUrl;
    if (assetInfoJsonUrl == null) {
      throw Exception('Could not find asset-info.json');
    }

    final httpClient = Client();
    final json = (await httpClient.get(Uri.parse(assetInfoJsonUrl))).body;
    final assetInfo =
        AssetInfo.fromJson(jsonDecode(json) as List<Map<String, String>>);

    final upgradables = {
      'rush.exe': p.join(Platform.resolvedExecutable),
      'swap.exe': p.join(p.dirname(Platform.resolvedExecutable), 'swap.exe'),
      'android.jar': p.join(_fs.libsDir.path, 'android.jar'),
      'annotations.jar': p.join(_fs.srcDir.path, 'annotations.jar'),
      'annotations-sources.jar':
          p.join(_fs.srcDir.path, 'annotations-sources.jar'),
      'runtime.jar': p.join(_fs.libsDir.path, 'runtime.jar'),
      'runtime-sources.jar': p.join(_fs.libsDir.path, 'runtime-sources.jar'),
      'kawa-1.11-modified.jar':
          p.join(_fs.libsDir.path, 'kawa-1.11-modified.jar'),
      'physicaloid-library.jar':
          p.join(_fs.libsDir.path, 'physicaloid-library.jar'),
      'processor-uber.jar': p.join(_fs.libsDir.path, 'processor-uber.jar'),
      'desugar.jar': p.join(_fs.libsDir.path, 'desugar.jar'),
    };

    for (final asset in assetInfo.assets) {
      if (!Platform.isWindows && asset.name == 'swap.exe') {
        continue;
      }

      final saveAs = asset.downloadLocation
          .replaceAll('{{home}}', _fs.rushHomeDir.path)
          .replaceAll('{{exe}}', Platform.resolvedExecutable);

      if (!upgradables.containsKey(asset.name)) {
        await _download(httpClient, asset.url, saveAs);
        continue;
      }

      final upgradable = upgradables[asset.name];
      final sha = sha1.convert(upgradable!.asFile().readAsBytesSync());
      if (sha.toString() == asset.sha1) {
        continue;
      }

      await _download(httpClient, asset.url, saveAs);
      if (saveAs != upgradable) {
        upgradable.asFile().deleteSync();
      }
    }

    if (Platform.isWindows) {
      final newExe = '${Platform.resolvedExecutable}.new';
      final swapExe =
          p.join(p.dirname(Platform.resolvedExecutable), 'swap.exe');
      if (newExe.asFile().existsSync()) {
        await Process.start(
            swapExe, ['--old-exe', Platform.resolvedExecutable]);
      }
    } else {
      final newExe = '${Platform.resolvedExecutable}.new';
      newExe.asFile().renameSync(newExe.replaceFirst('.new', ''));
      await Process.start('chmod', ['+x', Platform.resolvedExecutable]);
    }
  }

  Future<void> _download(Client client, String url, String saveAs) async {
    final response = await client.get(Uri.parse(url));
    saveAs.asFile().writeAsBytesSync(response.bodyBytes);
  }
}
