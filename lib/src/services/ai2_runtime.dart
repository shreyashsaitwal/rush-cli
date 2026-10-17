import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:get_it/get_it.dart';
import 'package:path/path.dart' as p;

import 'package:rush/src/commands/build/utils.dart';
import 'package:rush/src/resolver/artifact.dart';
import 'package:rush/src/resolver/maven.dart';
import 'package:rush/src/services/file_service.dart';
import 'package:rush/src/services/logger.dart';
import 'package:rush/src/utils/constants.dart';
import 'package:rush/src/utils/download.dart';
import 'package:rush/src/utils/file_extension.dart';

class Ai2Runtime {
  static final _fs = GetIt.I<FileService>();
  static final _lgr = GetIt.I<Logger>();

  Ai2Runtime._(this.dir, this.androidApi, this.libs, this.alwaysIncludedLibs);

  final String dir;

  final int androidApi;

  final List<Artifact> libs;

  final List<Artifact> alwaysIncludedLibs;

  String get androidJar => p.join(dir, 'libs', 'android.jar');

  String get runtimeJar => p.join(dir, 'libs', 'AndroidRuntime.jar');

  List<String> get resourceAars {
    if (!hasResources) {
      throw Exception('App Inventor\'s AndroidX resources aren\'t installed. '
          'Run `rush deps sync`.');
    }
    return [
      for (final file in _resourcesIndex.readAsLinesSync())
        if (file.isNotEmpty) p.join(_resourcesDir, file),
    ];
  }

  static String get _resourcesDir => p.join(_installDir, 'androidx');

  static File get _resourcesIndex =>
      p.join(_resourcesDir, 'index.txt').asFile();

  static bool get hasResources => _resourcesIndex.existsSync();

  static Future<void> installResources(Iterable<String> repositories) async {
    _lgr.info('Downloading the resources of App Inventor\'s AndroidX...');
    final runtime = await load();
    final tmpDir = '$_resourcesDir.tmp';
    if (await tmpDir.asDir().exists()) {
      await tmpDir.asDir().delete(recursive: true);
    }
    tmpDir.asDir(true);
    final resolver = MavenResolver(repositories: repositories);
    final files = <String>[];
    try {
      for (final library in runtime.alwaysIncludedLibs) {
        if (library.coordinate.split(':').length != 3) {
          continue;
        }
        final aar = await resolver.fetchAar(library.coordinate);
        if (aar != null) {
          files.add(p.basename(aar));
          await aar.asFile().copy(p.join(tmpDir, p.basename(aar)));
        }
      }
    } finally {
      await resolver.close();
    }
    await p
        .join(tmpDir, 'index.txt')
        .asFile()
        .writeAsString(files.map((el) => '$el\n').join());
    if (await _resourcesDir.asDir().exists()) {
      await _resourcesDir.asDir().delete(recursive: true);
    }
    await tmpDir.asDir().rename(_resourcesDir);
  }

  static String get _installDir =>
      p.join(_fs.rushHomeDir.path, 'ai2', ai2Version);

  static File get _manifestFile => p.join(_installDir, 'runtime.json').asFile();

  static bool get isInstalled => _manifestFile.existsSync();

  static Ai2Runtime? _loaded;

  static Future<Ai2Runtime> load() async {
    if (_loaded != null) {
      return _loaded!;
    }
    if (!isInstalled) {
      _lgr
        ..err('App Inventor runtime $ai2Version is not installed.')
        ..log('Run `rush deps sync --dev-deps` to install it.', 'help  ');
      throw Exception('App Inventor runtime $ai2Version is not installed');
    }

    final manifest =
        jsonDecode(await _manifestFile.readAsString()) as Map<String, dynamic>;
    final entries = (manifest['libs'] as List).cast<Map<String, dynamic>>();
    Artifact toArtifact(Map<String, dynamic> lib) {
      final file = p.join(_installDir, lib['file'] as String);
      return Artifact(
        coordinate: (lib['coordinate'] as String?) ?? p.basename(file),
        scope: Scope.provided,
        artifactFile: file,
        packaging: 'jar',
        dependencies: [],
        sourcesJar: null,
      );
    }

    return _loaded = Ai2Runtime._(
      _installDir,
      manifest['androidApi'] as int,
      entries.map(toArtifact).toList(),
      entries
          .where((el) => el['alwaysIncluded'] == true)
          .map(toArtifact)
          .toList(),
    );
  }

  static Future<void> install() async {
    final localZip = Platform.environment['RUSH_AI2_RUNTIME_ZIP'];
    final List<int> bytes;
    if (localZip != null && localZip.isNotEmpty) {
      _lgr.info('Installing App Inventor runtime $ai2Version from $localZip');
      bytes = await localZip.asFile().readAsBytes();
    } else {
      _lgr.info('Downloading App Inventor runtime $ai2Version...');
      final res = await download(Uri.parse(ai2RuntimeUrl));
      if (res.statusCode != 200) {
        throw Exception(
            'Failed to download $ai2RuntimeUrl (HTTP ${res.statusCode})');
      }
      bytes = res.bodyBytes;

      final checksum = sha256.convert(bytes).toString();
      if (checksum != ai2RuntimeSha256) {
        throw Exception('Checksum mismatch for $ai2RuntimeUrl: expected '
            '$ai2RuntimeSha256, got $checksum');
      }
    }

    final tmpZip = p.join(_fs.rushHomeDir.path, 'ai2', '$ai2Version.zip');
    final tmpDir = '$_installDir.tmp';
    await tmpZip.asFile(true).writeAsBytes(bytes);
    try {
      if (await tmpDir.asDir().exists()) {
        await tmpDir.asDir().delete(recursive: true);
      }
      await BuildUtils.unzip(tmpZip, tmpDir);
      if (await _installDir.asDir().exists()) {
        await _installDir.asDir().delete(recursive: true);
      }
      await tmpDir.asDir().rename(_installDir);
      _loaded = null;
    } finally {
      await tmpZip.asFile().delete();
    }
  }
}
