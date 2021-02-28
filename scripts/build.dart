import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:args/args.dart';
import 'package:path/path.dart' as p;
import 'package:dio/dio.dart';
import 'package:archive/archive.dart';
import 'package:rush_cli/templates/build_readme.dart';
import 'package:rush_cli/templates/build_xml.dart';
import 'package:rush_cli/templates/license_template.dart';

Future<void> main(List<String> args) async {
  final parser = ArgParser();
  parser
    ..addFlag('build_ap', abbr: 'a', defaultsTo: false)
    ..addFlag('build_exe', abbr: 'e', defaultsTo: true)
    ..addOption('ap_path', abbr: 'p')
    ..addOption('version', abbr: 'v');

  final res = parser.parse(args);

  await _getAnt();
  await _getAntContribAndD8();

  if (res['build_exe']) {
    await _buildExe();
  }
  if (res['build_ap'] && res['ap_path'].toString().isNotEmpty) {
    await _buildAp(res['ap_path']);
  } else {
    print('============= Skipping annotation processor build =============');
  }

  print('============= Writing other files =============');

  final license = File(p.join(p.current, 'build', 'LICENSE'));
  if (!license.existsSync()) {
    license
      ..createSync(recursive: true)
      ..writeAsStringSync(getLicense());
  }

  final readme = File(p.join(p.current, 'build', 'README.md'));
  if (!readme.existsSync()) {
    readme
      ..createSync(recursive: true)
      ..writeAsStringSync(getBuildReadme());
  }

  File(p.join(p.current, 'build', 'bin', 'build_info'))
    ..createSync(recursive: true)
    ..writeAsStringSync('''
name: ${res['version']}
built_on: ${DateTime.now().toUtc()}
''');

  print('============= Creating rush.zip =============');

  final rushZip = File(p.join(p.current, 'build', 'out', 'rush.zip'));
  if (rushZip.existsSync()) {
    rushZip.deleteSync();
  }

  final encoder = ZipFileEncoder();
  encoder.zipDirectory(Directory(p.join(p.current, 'build')),
      filename: rushZip.path);

  print('============= Done =============');
}

Future<void> _buildAp(String apRepoPath) async {
  if (!Directory(apRepoPath).existsSync()) {
    print('$apRepoPath not found.');
    exit(1);
  }
  print('============= Building annotation processor =============');
  final stream = Process.start('gradle', ['build', 'copyImpl'],
          runInShell: Platform.isWindows, workingDirectory: apRepoPath)
      .asStream()
      .asBroadcastStream();

  await for (final process in stream) {
    await for (List<int> data in process.stdout.asBroadcastStream()) {
      print(String.fromCharCodes(data).trimRight());
    }
  }
  _copyLibs(apRepoPath);
}

Future<void> _buildExe() async {
  print('============= Building rush.exe =============');
  final outDir = Directory(p.join(p.current, 'build', 'bin'))
    ..createSync(recursive: true);
  final wd = p.join(p.current, 'bin');
  final stream = Process.start('dart',
          ['compile', 'exe', '-o', '${outDir.path}/rush.exe', 'rush.dart'],
          runInShell: Platform.isWindows, workingDirectory: wd)
      .asStream()
      .asBroadcastStream();
  await for (final process in stream) {
    await for (List<int> data in process.stdout.asBroadcastStream()) {
      print(String.fromCharCodes(data).trimRight());
    }
  }
}

void _copyLibs(String apRepoPath) {
  print('============= Copying libraries =============');

  final runtimeLibs = p.join(apRepoPath, 'runtime', 'build', 'implementation');
  final runtimeDest = p.join(p.current, 'build', 'dev-deps');
  Directory(runtimeDest).createSync(recursive: true);
  _copyDir(runtimeLibs, runtimeDest, p.join(apRepoPath, 'build', 'temp_dir'));

  final procLibs = p.join(apRepoPath, 'processor', 'build', 'implementation');
  final procDest = p.join(p.current, 'build', 'tools', 'processor');
  Directory(procDest).createSync(recursive: true);
  _copyDir(procLibs, procDest, p.join(apRepoPath, 'build', 'temp_dir'));

  File(p.join(apRepoPath, 'processor', 'build', 'libs', 'processor-v186a.jar'))
      .copySync(procDest + '/processor-v186a.jar');

  final runtimeAar = p.join(apRepoPath, 'runtime', 'build', 'outputs', 'aar');
  _extractZip(runtimeAar + '/runtime-release.aar',
      p.join(apRepoPath, 'runtime', 'build', 'outputs', 'aar'), '');

  File(runtimeAar + '/classes.jar')
      .copySync(runtimeDest + '/runtime-v186a.jar');
}

void _copyDir(String src, String dest, String temp) {
  final srcDir = Directory(src);
  final destDir = Directory(dest);
  var files = srcDir.listSync();
  files.forEach((entity) async {
    if (entity is File) {
      if (p.basename(entity.path).endsWith('aar')) {
        final tempDir = p.join(temp, p.basenameWithoutExtension(entity.path));
        _extractZip(entity.path, tempDir, '== ${p.basename(entity.path)}.aar -> ${p.basename(entity.path)}.jar ==');

        final classesJar = File(p.join(tempDir, 'classes.jar'));
        classesJar.copySync(p.join(
            destDir.path, p.basenameWithoutExtension(entity.path) + '.jar'));
      } else {
        entity.copySync(p.join(destDir.path, p.basename(entity.path)));
      }
    } else if (entity is Directory) {
      var newDest =
          Directory(p.join(destDir.path, entity.path.split('\\').last));
      newDest.createSync();
      _copyDir(entity.path, newDest.path, temp);
    }
  });
}

Future<void> _getAnt() async {
  if (!Directory(p.join(p.current, 'build', 'tools', 'apache-ant-1.10.9'))
      .existsSync()) {
    await _download(
        'https://downloads.apache.org//ant/binaries/apache-ant-1.10.9-bin.zip',
        p.join(p.current, 'build', 'tools', 'apache-ant.zip'),
        'Downloading apache-ant...');
    _extractZip(p.join(p.current, 'build', 'tools', 'apache-ant.zip'),
        p.join(p.current, 'build', 'tools'), 'Extracting apache-ant.zip...');

    File(p.join(p.current, 'build', 'tools', 'apache-ant-1.10.9', 'build.xml'))
      ..createSync(recursive: true)
      ..writeAsStringSync(getBuildXml());
  }
}

Future<void> _getAntContribAndD8() async {
  if (!Directory(p.join(p.current, 'build', 'tools', 'ant-contrib'))
      .existsSync()) {
    await _download(
        'https://drive.google.com/uc?id=1c4EXJcJigoUEtKs6-CZkEuculWkZ5xvJ&export=download',
        p.join(p.current, 'build', 'tools', 'ant-contrib.zip'),
        'Downloading ant-contrib...');
    _extractZip(p.join(p.current, 'build', 'tools', 'ant-contrib.zip'),
        p.join(p.current, 'build', 'tools'), 'Extracting ant-contrib.zip...');
  }

  if (!File(p.join(p.current, 'build', 'tools', 'd8.jar')).existsSync()) {
    await _download(
        'https://drive.google.com/u/0/uc?id=1iBjBaX07HbF9JZBVRtGntk5wXaFRCuFE&export=download',
        p.join(p.current, 'build', 'tools', 'd8.jar'),
        'Downloading D8...');
  }
}

bool _isSignificantIncrease(int total, int cur, int prev) {
  if (prev < 1) {
    return true;
  }
  var prevPer = (prev / total) * 100;
  var curPer = (cur / total) * 100;
  if ((curPer - prevPer) >= 1) {
    return true;
  }
  return false;
}

Future<void> _download(String downloadUrl, String saveTo, String title) async {
  print(title);
  try {
    var prev = 0;
    await Dio().download(
      downloadUrl,
      saveTo,
      deleteOnError: true,
      cancelToken: CancelToken(),
      onReceiveProgress: (count, total) {
        if (total != -1 && _isSignificantIncrease(total, count, prev)) {
          prev = count;
        }
      },
    );
  } catch (e) {
    print(e.toString());
  }
}

void _extractZip(String filePath, String saveTo, String title) {
  final file = File(filePath);
  if (!file.existsSync()) {
    print('Unable to extract zip [${file.path}]. Aborting...');
  }

  final bytes = file.readAsBytesSync();
  final zip = ZipDecoder().decodeBytes(bytes).files;

  print(title);
  for (var i = 0; i < zip.length; i++) {
    if (zip[i].isFile) {
      final data = zip[i].content;
      try {
        File(p.join(saveTo, zip[i].name))
          ..createSync(recursive: true)
          ..writeAsBytesSync(data);
      } catch (e) {
        print(e.toString());
      }
    }
  }

  file.deleteSync();
}
