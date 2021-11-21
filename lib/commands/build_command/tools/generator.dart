import 'dart:io'
    show
        Directory,
        File,
        HttpClient,
        HttpClientRequest,
        HttpClientResponse,
        exit;

import 'package:archive/archive.dart';
import 'package:http/http.dart';
import 'package:path/path.dart' as p;
import 'package:rush_cli/commands/build_command/helpers/compute.dart';
import 'package:rush_cli/commands/build_command/models/rush_yaml.dart';
import 'package:rush_cli/helpers/dir_utils.dart';
import 'package:rush_cli/version.dart';
import 'package:rush_prompt/rush_prompt.dart';
import 'package:http/http.dart' as http;

class Generator {
  final String _cd;
  final String _dataDir;

  Generator(this._cd, this._dataDir);

  /// Generates required extension files.
  Future<void> generate(String org, BuildStep step, RushYaml yaml) async {
    await Future.wait([
      _generateInfoFiles(org),
      _copyAssets(yaml, org, step),
      _copyLicense(org, yaml),
      _copyRequiredClasses(yaml, org, step)
    ]);
  }

  Future<void> download(String org, BuildStep step, RushYaml yaml) async {
    await Future.wait([_downloadDeps(yaml, org, step)]);
  }

  /// Generates the components info, build, and the properties file.
  Future<void> _generateInfoFiles(String org) async {
    final rawDirX =
        Directory(p.join(_dataDir, 'workspaces', org, 'raw', 'x', org));
    await rawDirX.create(recursive: true);

    final filesDirPath = p.join(_dataDir, 'workspaces', org, 'files');

    // Copy the components.json file to the raw dir.
    final simpleCompJson = File(p.join(filesDirPath, 'components.json'));
    await simpleCompJson.copy(p.join(rawDirX.path, 'components.json'));

    // Copy the component_build_infos.json file to the raw dir.
    final buildInfoJson =
        File(p.join(filesDirPath, 'component_build_infos.json'));

    final rawFilesDir = Directory(p.join(rawDirX.path, 'files'));
    await rawFilesDir.create(recursive: true);

    await buildInfoJson
        .copy(p.join(rawFilesDir.path, 'component_build_infos.json'));

    // Write the extension.properties file
    await File(p.join(rawDirX.path, 'extension.properties')).writeAsString('''
type=external
rush-version=$rushVersion
''');
  }

  /// Copies extension's assets to the raw directory.
  Future<void> _copyAssets(RushYaml rushYml, String org, BuildStep step) async {
    final assets = rushYml.assets.other ?? [];

    if (assets.isNotEmpty) {
      final assetsDir = p.join(_cd, 'assets');
      final assetsDestDirX = Directory(
          p.join(_dataDir, 'workspaces', org, 'raw', 'x', org, 'assets'));
      await assetsDestDirX.create(recursive: true);

      for (final el in assets) {
        final asset = File(p.join(assetsDir, el));

        if (asset.existsSync()) {
          await asset.copy(p.join(assetsDestDirX.path, el));
        } else {
          step.log(LogType.warn,
              'Unable to find asset "${p.basename(el)}". Skipping.');
        }
      }
    }

    // Pattern to match URL
    final urlPattern = RegExp(
        r'https?:\/\/(www\.)?[-a-zA-Z0-9@:%._\+~#=]{1,256}\.[a-zA-Z0-9()]{1,6}\b([-a-zA-Z0-9()!@:%_\+.~#?&\/\/=]*)',
        dotAll: true);

    final iconName = rushYml.assets.icon;

    if (!urlPattern.hasMatch(iconName) && iconName != '') {
      final icon = File(p.join(_cd, 'assets', iconName));
      final iconDestDir = Directory(
          p.join(_dataDir, 'workspaces', org, 'raw', 'x', org, 'aiwebres'));

      await iconDestDir.create(recursive: true);
      await icon.copy(p.join(iconDestDir.path, iconName));
    }
  }

  Future<void> _downloadDeps(
      RushYaml rushYml, String org, BuildStep step) async {
    final deps = rushYml.deps ?? [];

    if (deps.isNotEmpty) {
      String artId = "";
      String version = "";
      String packageName = "";
      File dep;
      String path;
      File temp;
      String tempPath;
      for (String el in deps) {
        if (el.contains(':')) {
          final repos = [
            "https://maven.google.com",
            "https://jcenter.bintray.com",
            "https://repo.maven.apache.org/maven2",
            "https://repository.jboss.org/nexus/content/repositories/releases",
            "https://repo.clojars.org"
          ];
          // print(repos);
          final arr = el.split(':');
          version = arr[2];
          artId = arr[1];
          packageName = arr[0];
          path = p.join(_cd, 'deps', artId + "-" + version + ".aar");
          tempPath = p.join(_dataDir, artId + "-" + version + ".aar");
          temp = new File(tempPath);
          temp.create(recursive: true);
          for (var i = 0; i < repos.length; i++) {
            final String url = repos[i] +
                "/" +
                packageName.replaceAll('.', '/') +
                "/" +
                artId +
                "/" +
                version +
                "/" +
                artId +
                "-" +
                version +
                ".aar";

            Response response = await get(Uri.parse(url));
            if (response.statusCode == 200) {
              await temp.writeAsBytes(response.bodyBytes);
              break;
            } else {
              final String url = repos[i] +
                  "/" +
                  packageName.replaceAll('.', '/') +
                  "/" +
                  artId +
                  "/" +
                  version +
                  "/" +
                  artId +
                  "-" +
                  version +
                  ".jar";
              String path = p.join(_cd, 'deps', artId + "-" + version + ".jar");
              Response response = await get(Uri.parse(url));
              if (response.statusCode == 200) {
                new File(path).writeAsBytes(response.bodyBytes);
                break;
              } else {
                String fName = artId + "-" + version + ".jar";
                if (i == repos.length - 1) {
                  step
                    ..log(LogType.erro,
                        'Unable to download required library \'${el}\'')
                    ..finishNotOk();

                  exit(1);
                }
              }
            }
          }

          final bytes = temp.readAsBytesSync();
          final archive = new ZipDecoder().decodeBytes(bytes);
          for (var file in archive) {
            final filename = path.replaceAll(".aar", ".jar");
            if (file.isFile && file.name.endsWith(".jar")) {
              var outFile = new File(filename);
              outFile = await outFile.create(recursive: true);
              await outFile.writeAsBytes(file.content);
            }
          }
          temp.deleteSync();
        }
      }
      step
        ..log(LogType.info, 'Successfully Downloaded Dependencies')
        ..finishOk();
    }
  }

  /// Unjars extension dependencies into the classes dir.
  Future<void> _copyRequiredClasses(
      RushYaml rushYml, String org, BuildStep step) async {
    final deps = rushYml.deps ?? [];
    final artDir = Directory(p.join(_dataDir, 'workspaces', org, 'art'))
      ..createSync(recursive: true);

    final extractFutures = <Future<ErrWarnStore>>[];

    if (deps.isNotEmpty) {
      final desugarStore =
          p.join(_dataDir, 'workspaces', org, 'files', 'desugar');
      final isArtDirEmpty = artDir.listSync().isEmpty;

      for (String el in deps) {
        File dep;
        String fName = el;
        if (el.contains(':')) {
          final arr = el.split(':');
          String version = arr[2];
          String artId = arr[1];
          String packageName = arr[0];
          fName = artId + "-" + version + ".jar";
        }
        if (rushYml.build?.desugar?.desugar_deps ?? false) {
          dep = File(p.join(desugarStore, fName));
        } else {
          dep = File(p.join(_cd, 'deps', fName));
        }

        if (!dep.existsSync()) {
          step
            ..log(LogType.erro,
                'Unable to find required library \'${p.basename(dep.path)}\'')
            ..finishNotOk();
          exit(1);
        }

        final isLibModified = dep.existsSync()
            ? dep.lastModifiedSync().isAfter(artDir.statSync().modified)
            : true;

        if (isLibModified || isArtDirEmpty) {
          extractFutures.add(compute(_extractJar,
              _ExtractJarArgs(input: dep.path, outputDir: artDir.path)));
        }
      }
    }

    final kotlinEnabled = rushYml.build?.kotlin?.enable ?? false;

    // If Kotlin is enabled, unjar Kotlin std. lib as well.
    // This step won't be needed once MIT merges the Kotlin support PR.
    if (kotlinEnabled) {
      final kotlinStdLib =
          File(p.join(_dataDir, 'dev-deps', 'kotlin', 'kotlin-stdlib.jar'));

      extractFutures.add(compute(_extractJar,
          _ExtractJarArgs(input: kotlinStdLib.path, outputDir: artDir.path)));
    }

    final classesDir =
        Directory(p.join(_dataDir, 'workspaces', org, 'classes'));

    classesDir.listSync(recursive: true).whereType<File>().forEach((el) {
      final newPath =
          p.join(artDir.path, p.relative(el.path, from: classesDir.path));
      Directory(p.dirname(newPath)).createSync(recursive: true);
      el.copySync(newPath);
    });

    final results = await Future.wait(extractFutures);

    final store = ErrWarnStore();
    for (final result in results) {
      store.incErrors(result.getErrors);
      store.incWarnings(result.getWarnings);
    }
  }

  /// Copies LICENSE file if there's any.
  Future<void> _copyLicense(String org, RushYaml yaml) async {
    // Pattern to match URL
    final urlPattern = RegExp(
        r'https?:\/\/(www\.)?[-a-zA-Z0-9@:%._\+~#=]{1,256}\.[a-zA-Z0-9()]{1,6}\b([-a-zA-Z0-9()!@:%_\+.~#?&\/\/=]*)',
        dotAll: true);

    final File license;
    if (yaml.license != null && !urlPattern.hasMatch(yaml.license!)) {
      license = File(p.join(_cd, yaml.license));
    } else {
      return;
    }

    final dest = Directory(
        p.join(_dataDir, 'workspaces', org, 'raw', 'x', org, 'aiwebres'));
    await dest.create(recursive: true);

    if (license.existsSync()) {
      await license.copy(p.join(dest.path, 'LICENSE'));
    }
  }

  /// Extracts JAR file from [input] and saves the content to [outputDir].
  static ErrWarnStore _extractJar(_ExtractJarArgs args) {
    final step = BuildStep('');

    final file = File(args.input);

    final bytes = file.readAsBytesSync();
    final jar = ZipDecoder().decodeBytes(bytes).files;

    for (final entity in jar) {
      if (entity.isFile) {
        final data = entity.content as List<int>;
        try {
          File(p.join(args.outputDir, entity.name))
            ..createSync(recursive: true)
            ..writeAsBytesSync(data);
        } catch (e) {
          step
            ..log(LogType.erro, e.toString())
            ..finishNotOk();
          exit(1);
        }
      }
    }

    return ErrWarnStore();
  }
}

class _ExtractJarArgs {
  final String input;
  final String outputDir;

  _ExtractJarArgs({required this.input, required this.outputDir});
}
