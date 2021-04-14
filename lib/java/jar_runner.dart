import 'dart:io' show Directory, File, Platform;

import 'package:process_runner/process_runner.dart';
import 'package:path/path.dart' as p;
import 'package:rush_cli/java/helper.dart';
import 'package:rush_cli/mixins/app_data_dir_mixin.dart';
import 'package:rush_cli/mixins/copy_mixin.dart';
import 'package:rush_prompt/rush_prompt.dart';

enum JarType { processor, d8, d8sup, proguard, jar, jetifier }

class JarRunner with AppDataMixin, CopyMixin {
  final _cd = p.current;
  final _rushDir = p.dirname(p.dirname(Platform.resolvedExecutable));

  /// Runs the specified [type] of JAR, printing the required stdout and the whole
  /// stderr.
  ///
  /// If any error is caught, the [onError] function is invoked.
  ///
  /// If everything goes well, the [onSuccess] function is invoked.
  void run(JarType type, String org, BuildStep step,
      {required Function onSuccess, required Function onError}) {
    final args = <String>[];
    var dwd = _cd; // Default working directory

    switch (type) {
      case JarType.processor:
        args.addAll(_getProcessorArgs(org));
        break;
      case JarType.d8:
        args.addAll(_getD8Args(org, false));
        break;
      case JarType.d8sup:
        args.addAll(_getD8Args(org, true));
        break;
      case JarType.jar:
        dwd = p.join(dataStorageDir()!, 'workspaces', org, 'raw-classes', org);
        args.addAll(_getJarArgs(org, dwd));
        break;
      case JarType.proguard:
        args.addAll(_getPgArgs(org));
        break;
      case JarType.jetifier:
        args.addAll(_getJetifierArgs(org));
        break;
    }

    var failed = false;
    var needDejet = true;

    ProcessRunner(defaultWorkingDirectory: Directory(dwd))
        .runProcess(args)
        .asStream()
        .asBroadcastStream()
        .listen((_) {})
          ..onData((data) {
            if (type == JarType.jetifier) {
              final pattern =
                  RegExp(r'WARNING: \[Main\] No references were rewritten.');

              if (needDejet) {
                needDejet = !data.stdout.contains(pattern);
              }
            }
          })
          ..onError((e) {
            final errList = e.result.stderr.split('\n');
            errList.forEach((err) {
              if (err.trim() != '' && err.trim() != null) {
                if (err.startsWith(RegExp(r'\s'))) {
                  if (type == JarType.proguard) {
                    step.logWarn(err, addPrefix: false);
                  } else {
                    step.logErr(err, addPrefix: false);
                  }
                } else {
                  final errPattern =
                      RegExp(r'error:?\s?', caseSensitive: false);

                  if (err.startsWith(errPattern)) {
                    err = err.replaceAll(errPattern, '');
                    step.logErr(err, addSpace: true);
                  } else if (type == JarType.proguard &&
                      err.startsWith('Warning: ')) {
                    err = err.replaceAll('Warning: ', '');
                    step.logWarn(err, addSpace: true);
                  } else {
                    step.logErr(err, addSpace: true);
                  }
                }
              }
            });
            failed = true;
          })
          ..onDone(() {
            if (failed) {
              onError();
            } else {
              if (type == JarType.jetifier) {
                onSuccess(needDejet);
              } else {
                onSuccess();
              }
            }
          });
  }

  /// Returns the args required for running the annotation processor.
  List<String> _getProcessorArgs(String org) {
    final args = <String>['java'];

    final devDeps = Directory(p.join(_cd, '.rush', 'dev-deps'));
    final processor = Directory(p.join(_rushDir, 'tools', 'processor'));

    final classpath = Helper.generateClasspath([devDeps, processor]);

    final classesDir =
        Directory(p.join(dataStorageDir()!, 'workspaces', org, 'classes'));
    final rawClassesDir =
        Directory(p.join(dataStorageDir()!, 'workspaces', org, 'raw-classes'))
          ..createSync(recursive: true);
    final rawDirX =
        Directory(p.join(dataStorageDir()!, 'workspaces', org, 'raw', 'x'))
          ..createSync(recursive: true);

    final deps = p.join(_cd, 'deps');

    args
      ..addAll(['-cp', classpath])
      ..add('io.shreyash.rush.ExtensionGenerator')
      ..addAll([
        p.join(classesDir.path, 'simple_components.json'),
        p.join(classesDir.path, 'simple_components_build_info.json'),
        rawDirX.path,
        classesDir.path,
        deps,
        rawClassesDir.path,
        'false',
        _cd,
      ]);

    return args;
  }

  /// Returns the args required for running D8.
  List<String> _getD8Args(String org, bool isSup) {
    final args = <String>['java'];

    final d8 = File(p.join(_rushDir, 'tools', 'd8.jar'));
    final rawOrgDirX = Directory(
        p.join(dataStorageDir()!, 'workspaces', org, 'raw', 'x', org));
    final rawOrgDirSup = Directory(
        p.join(dataStorageDir()!, 'workspaces', org, 'raw', 'sup', org));

    final rawPath = isSup ? rawOrgDirSup.path : rawOrgDirX.path;
    args
      ..addAll(['-cp', d8.path])
      ..add('com.android.tools.r8.D8')
      ..addAll([
        '--release',
        '--no-desugaring',
        '--output',
        p.join(rawPath, 'classes.jar'),
        p.join(rawPath, 'files', 'AndroidRuntime.jar'),
      ]);

    return args;
  }

  /// Returns the args required for running the jar tool, which is used create a JAR.
  List<String> _getJarArgs(String org, String dwd) {
    final args = <String>['jar.exe', 'cf', '../$org.jar'];

    final rawClassesOrgDir = Directory(dwd);

    // Add everything that needs to be jarred
    for (final entity in rawClassesOrgDir.listSync()) {
      if (entity is Directory) {
        args.add(p.relative(entity.path, from: dwd));
      } else if (p.extension(entity.path) == '.class') {
        args.add(p.relative(entity.path));
      }
    }

    return args;
  }

  /// Returns the args required for running ProGuard
  List<String> _getPgArgs(String org) {
    final proguardJar = File(p.join(_rushDir, 'tools', 'proguard.jar'));

    final devDeps = Directory(p.join(_cd, '.rush', 'dev-deps'));
    final deps = Directory(p.join(_cd, 'deps'));

    final libraryJars = Helper.generateClasspath([devDeps, deps]);

    final rawClasses =
        Directory(p.join(dataStorageDir()!, 'workspaces', org, 'raw-classes'));
    final injar = File(p.join(rawClasses.path, '$org.jar'));
    final outjar = File(p.join(rawClasses.path, '${org}_pg.jar'));

    final pgRules = File(p.join(_cd, 'src', 'proguard-rules.pro'));

    final args = <String>['java', '-jar', proguardJar.path];
    args
      ..addAll(['-injars', injar.path])
      ..addAll(['-outjars', outjar.path])
      ..addAll(['-libraryjars', libraryJars])
      ..add('@${pgRules.path}');

    return args;
  }

  /// Returns the args required for running jetifier-standalone.
  List<String> _getJetifierArgs(String org) {
    final rawOrgDir = Directory(
        p.join(dataStorageDir()!, 'workspaces', org, 'raw', 'x', org));
    final rawOrgDirSup = Directory(
        p.join(dataStorageDir()!, 'workspaces', org, 'raw', 'sup', org))
      ..createSync(recursive: true);

    copyDir(rawOrgDir, rawOrgDirSup);

    final androidRuntimeSup =
        File(p.join(rawOrgDirSup.path, 'files', 'AndroidRuntime.jar'));

    final exe;
    if (Platform.isWindows) {
      exe = p.join(_rushDir, 'tools', 'jetifier-standalone', 'bin',
          'jetifier-standalone.bat');
    } else {
      exe = p.join(_rushDir, 'tools', 'jetifier-standalone', 'bin',
          'jetifier-standalone');
    }

    final args = <String>[exe];
    args
      ..addAll(['-i', androidRuntimeSup.path])
      ..addAll(['-o', androidRuntimeSup.path])
      ..add('-r');

    return args;
  }
}
