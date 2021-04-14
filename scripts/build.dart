import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:args/args.dart';
import 'package:path/path.dart' as p;
import 'package:dio/dio.dart';
import 'package:archive/archive.dart';
import 'package:process_run/shell.dart';
import 'package:rush_cli/templates/license-apache.dart';
import 'package:rush_cli/templates/license_template.dart';

Future<void> main(List<String> args) async {
  final parser = ArgParser();
  parser
    ..addFlag('build_exe', abbr: 'e', defaultsTo: true)
    ..addFlag('ci', abbr: 'c', defaultsTo: false)
    ..addOption('ap_path', abbr: 'p')
    ..addOption('version', abbr: 'v');

  final res = parser.parse(args);

  await _getJetifier();
  await _getProGuard();

  if (res['build_exe']) {
    await _buildExe();
  }
  if (res['ap_path'] != null) {
    await _buildAp(res['ap_path']);
  } else if (res['ci']) {
    print('============= Copying files =============');

    final deps = Directory(p.join('temp', 'dev-deps'));
    final runtime = File(p.join('temp', 'runtime-release.aar'));

    final procLibs = Directory(p.join('temp', 'processor-libs'));
    final proc = File(p.join('temp', 'processor-v186a.jar'));

    final tempDirForRuntime = Directory(p.join('temp', 'runtime-temp'))
      ..createSync(recursive: true);
    _extractZip(
        runtime.path, tempDirForRuntime.path, 'Extracting runtime.jar...');
    final runtimeCls = File(p.join(tempDirForRuntime.path, 'classes.jar'));

    _copyDir(deps.path, p.join('build', 'dev-deps'), p.join('temp', 'temp'));
    runtimeCls.copySync(p.join('build', 'dev-deps', 'runtime-v186a.jar'));

    _copyDir(procLibs.path, p.join('build', 'tools', 'processor'),
        p.join('temp', 'temp'));
    proc.copySync(p.join('build', 'tools', 'processor', 'processor-v186a.jar'));

    File(p.join('build', 'dev-deps', 'android-2.1.2.jar'))
        .deleteSync(recursive: true);

    print('============= Downloading android.jar =============');
    final androidJar = File(p.join('build', 'dev-deps', 'android.jar'));
    await _download(
        'https://github.com/mit-cml/appinventor-sources/raw/master/appinventor/lib/android/android-29/android.jar',
        androidJar.path,
        'Downloading android.jar...');
  }

  print('============= Writing other files =============');

  final license = File(p.join(p.current, 'build', 'LICENSE.txt'));
  if (!license.existsSync()) {
    license
      ..createSync(recursive: true)
      ..writeAsStringSync(getLicense());
  }

  final apacheLicense =
      File(p.join(p.current, 'build', 'LICENSE-Apache-2.0.txt'));
  if (!apacheLicense.existsSync()) {
    apacheLicense
      ..createSync(recursive: true)
      ..writeAsStringSync(getApacheLicense());
  }

  final iconDest = File(p.join(p.current, 'build', 'tools', 'icon-rush.png'));
  final iconSrc = File(p.join(p.current, 'assets', 'icon-ext.png'));
  iconSrc.copySync(iconDest.path);

  File(p.join(p.current, 'build', 'bin', 'build_info'))
    ..createSync(recursive: true)
    ..writeAsStringSync('''
name: ${res['version']}
built_on: ${DateTime.now().toUtc()}
''');

  if (!res['ci']) {
    print('============= Creating rush archive =============');
    if (Platform.isWindows) {
      _createZip();
    } else {
      await _createTarGz();
    }
  }

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
  await _copyLibs(apRepoPath);
}

Future<void> _buildExe() async {
  print('============= Building rush executable =============');
  final outDir = Directory(p.join(p.current, 'build', 'bin'))
    ..createSync(recursive: true);
  final wd = p.join(p.current, 'bin');

  final exePath;
  if (Platform.isWindows) {
    exePath = p.join(outDir.path, 'rush.exe');
  } else {
    exePath = p.join(outDir.path, 'rush');
  }

  final stream = Process.start(
          'dart', ['compile', 'exe', '-o', exePath, 'rush.dart'],
          runInShell: Platform.isWindows, workingDirectory: wd)
      .asStream()
      .asBroadcastStream();
  await for (final process in stream) {
    await for (List<int> data in process.stdout.asBroadcastStream()) {
      print(String.fromCharCodes(data).trimRight());
    }
  }
}

Future<void> _copyLibs(String apRepoPath) async {
  print('============= Copying libraries =============');

  // Copy annotation processor and its dependencies
  final procLibs = p.join(apRepoPath, 'processor', 'build', 'implementation');
  final procDest = p.join(p.current, 'build', 'tools', 'processor');
  Directory(procDest).createSync(recursive: true);
  _copyDir(procLibs, procDest, p.join(apRepoPath, 'build', 'temp_dir'));
  File(p.join(apRepoPath, 'processor', 'build', 'libs', 'processor-v186a.jar'))
      .copySync(procDest + '/processor-v186a.jar');

  // Copy dev deps
  final runtimeLibs = p.join(apRepoPath, 'runtime', 'build', 'implementation');
  final devDepsDir = p.join(p.current, 'build', 'dev-deps');
  Directory(devDepsDir).createSync(recursive: true);
  _copyDir(runtimeLibs, devDepsDir, p.join(apRepoPath, 'build', 'temp_dir'));

  // Copy runtime.jar
  final runtimeAar = p.join(apRepoPath, 'runtime', 'build', 'outputs', 'aar');
  _extractZip(runtimeAar + '/runtime-release.aar',
      p.join(apRepoPath, 'runtime', 'build', 'outputs', 'aar'), '');
  File(runtimeAar + '/classes.jar').copySync(devDepsDir + '/runtime-v186a.jar');

  // Download android.jar if it doesn't exists
  final androidJar = p.join(devDepsDir, 'android.jar');
  if (!File(androidJar).existsSync()) {
    await _download(
        'https://github.com/mit-cml/appinventor-sources/raw/master/appinventor/lib/android/android-29/android.jar',
        androidJar,
        'Downloading android.jar...');
  }

  // Delete android-2.1.2.jar
  File(p.join(devDepsDir, 'android-2.1.2.jar')).deleteSync();
}

void _createZip() {
  final outDir = Directory(p.join(p.current, 'build', 'out'));
  if (outDir.existsSync()) {
    outDir.deleteSync(recursive: true);
  }

  final temp = Directory(p.join(p.current, 'temp'))..createSync();

  final encoder = ZipFileEncoder();
  encoder.zipDirectory(Directory(p.join(p.current, 'build')),
      filename: p.join(temp.path, 'rush.zip'));

  outDir.createSync();
  File(p.join(temp.path, 'rush.zip')).copySync(p.join(outDir.path, 'rush.zip'));
  temp.deleteSync(recursive: true);
}

Future<void> _createTarGz() async {
  await Shell().run('''
chmod +x build/bin/rush
tar -czf rush.tar.gz -C build *
''');
}

void _copyDir(String src, String dest, String temp) {
  final srcDir = Directory(src);
  final destDir = Directory(dest)..createSync(recursive: true);
  Directory(temp).createSync(recursive: true);
  var files = srcDir.listSync();
  files.forEach((entity) {
    if (entity is File) {
      if (p.basename(entity.path).endsWith('aar')) {
        final tempDir = p.join(temp, p.basenameWithoutExtension(entity.path));
        _extractZip(entity.path, tempDir,
            '${p.basenameWithoutExtension(entity.path)}.aar -> ${p.basenameWithoutExtension(entity.path)}.jar');

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

Future<void> _getJetifier() async {
  if (!Directory(p.join(p.current, 'build', 'tools', 'jetifier-standalone'))
      .existsSync()) {
    await _download(
        'https://dl.google.com/dl/android/studio/jetifier-zips/1.0.0-beta09/jetifier-standalone.zip',
        p.join(p.current, 'build', 'tools', 'jetifier-standalone.zip'),
        'Downloading Jetifier standalone...');

    _extractZip(p.join(p.current, 'build', 'tools', 'jetifier-standalone.zip'),
        p.join(p.current, 'build', 'tools'), 'Extracting Jetifier...');
  }
}

Future<void> _getProGuard() async {
  if (!Directory(p.join(p.current, 'build', 'tools', 'proguard'))
      .existsSync()) {
    await _download(
        'https://drive.google.com/u/0/uc?id=1gFu4-Qfa7efOubQERd0U6n8IlaHdludm&export=download',
        p.join(p.current, 'build', 'tools', 'proguard'),
        'Downloading ProGuard...');

    _extractZip(p.join(p.current, 'build', 'tools', 'proguard'),
        p.join(p.current, 'build', 'tools'), 'Extracting ProGuard...');
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

Future<void> _download(String downloadUrl, String saveAs, String title) async {
  print(title);
  try {
    var prev = 0;
    await Dio().download(
      downloadUrl,
      saveAs,
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
