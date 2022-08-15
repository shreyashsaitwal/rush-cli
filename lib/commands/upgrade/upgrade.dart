// TODO: Reimplement

// import 'dart:io'
//     show Directory, File, Platform, Process, ProcessStartMode, exit;

// import 'package:get_it/get_it.dart';
// import 'package:hive/hive.dart';
// import 'package:path/path.dart' as p;
// import 'package:rush_cli/commands/rush_command.dart';
// import 'package:rush_cli/commands/upgrade/models/repo_content.dart';
// import 'package:rush_cli/commands/upgrade/models/gh_release.dart';
// import 'package:rush_cli/services/file_service.dart';
// import 'package:rush_cli/version.dart';

// class UpgradeCommand extends RushCommand {
//   final FileService _fs = GetIt.I<FileService>();
//   static const String _endpt = 'https://rush-api.shreyashsaitwal.repl.co';

//   UpgradeCommand() {
//     argParser
//       ..addFlag('force',
//           abbr: 'f',
//           help:
//               'Forcefully upgrades Rush to the latest version. This downloads '
//               'and replaces even the unchanged files.')
//       ..addFlag('safe', abbr: 's', hide: true);
//   }

//   @override
//   String get description => 'Upgrades Rush to the latest available version.';

//   @override
//   String get name => 'upgrade';

//   @override
//   Future<void> run() async {
//     final dir = Directory(p.join(_fs.dataDir, '.installer'));
//     await dir.create(recursive: true);
//     Hive.init(dir.path);

//     final isForce = argResults?['force'] as bool;
//     final initDataBox = await Hive.openBox('data.init');

//     Logger.log(LogType.info, 'Fetching data...');
//     final allContent = await _fetchAllContent(initDataBox);
//     final reqContent = await _reqContents(initDataBox, allContent, isForce);

//     final releaseInfo = await _fetchLatestRelease();

//     if (releaseInfo.name == 'v$rushVersion' && !isForce) {
//       Logger.log(LogType.warn,
//           'You already have the latest version of Rush ($rushVersion) installed.');
//       Logger.log(LogType.note,
//           'To perform a force upgrade, run `rush upgrade --force`');
//       exit(0);
//     }

//     final binDir = p.dirname(Platform.resolvedExecutable);

//     Logger.log(
//         LogType.info, 'Starting download... [${reqContent.length} MB]\n');
//     final ProgressBar pb = ProgressBar(reqContent.length);

//     for (final el in reqContent) {
//       final savePath = () {
//         if (el.path!.startsWith('exe')) {
//           return p.join(binDir, el.name! + '.new');
//         }
//         return p.join(_fs.dataDir, el.path);
//       }();

//       await Dio().download(el.downloadUrl!, savePath);
//       await _updateInitBox(initDataBox, el, savePath);
//       pb.incr();
//     }

//     Logger.log(
//         LogType.info, 'Download complete; performing post download tasks...');
//     if (!(argResults?['safe'] as bool)) {
//       await _removeRedundantFiles(initDataBox, allContent);
//     }
//     await _swapExe(binDir);

//     Logger.log(LogType.info,
//         'Done! Rush was successfully upgraded to ${releaseInfo.name}');
//   }

//   /// Returns a list of all the files that needs to be downloaded from GH.
//   Future<List<RepoContent>> _reqContents(
//       Box initDataBox, List<RepoContent> contents, bool force) async {
//     // If this is a forceful upgrade, return all the files, else only the ones
//     // that have changed.
//     if (force) {
//       return contents;
//     }

//     final res = <RepoContent>[];
//     for (final el in contents) {
//       final data = await initDataBox.get(el.name);

//       // Stage this file for download if: 1. data is null or 2. it's sha doesn't
//       // match with that of upstream or 3. it doesn't exist at the expected
//       // location.
//       if (data == null) {
//         res.add(el);
//       } else {
//         final idealPath = File(p.join(_fs.dataDir, el.path));
//         if (el.sha != data['sha'] || !await idealPath.exists()) {
//           res.add(el);
//         }
//       }
//     }

//     return res;
//   }

//   /// Removes all the files that are no longer needed.
//   Future<void> _removeRedundantFiles(
//       Box initDataBox, List<RepoContent> contents) async {
//     final entriesInBox = initDataBox.keys;

//     final devDepsToRemove = Directory(p.join(_fs.dataDir, 'dev-deps'))
//         .listSync(recursive: true)
//         .whereType<File>()
//         .where((file) => !contents
//             .any((el) => el.path == p.relative(file.path, from: _fs.dataDir)));

//     final toolsToRemove = Directory(p.join(_fs.dataDir, 'tools'))
//         .listSync(recursive: true)
//         .whereType<File>()
//         .where((file) => !contents
//             .any((el) => el.path == p.relative(file.path, from: _fs.dataDir)));

//     for (final file in [...devDepsToRemove, ...toolsToRemove]) {
//       // Remove box entry of this file if it exists
//       final basename = p.basename(file.path);
//       if (entriesInBox.contains(basename)) {
//         await initDataBox.delete(basename);
//       }

//       try {
//         await file.delete();
//       } catch (_) {}
//     }
//   }

//   /// Returns all the files that are changed since the last release and needs to
//   /// be updated.
//   Future<List<RepoContent>> _fetchAllContent(Box initDataBox) async {
//     final Response response;
//     try {
//       response = await Dio().get('$_endpt/contents');
//     } catch (e) {
//       Logger.log(LogType.erro, 'Something went wrong:');
//       Logger.log(LogType.erro, e.toString(), addPrefix: false);
//       exit(1);
//     }

//     final json = response.data as List;

//     final contents = json
//         .map((el) => RepoContent.fromJson(el as Map<String, dynamic>))
//         .where((el) {
//       if (el.path!.startsWith('exe')) {
//         return el.path!.contains(_correctExePath());
//       }
//       return true;
//     });

//     return contents.toList();
//   }

//   String _correctExePath() {
//     switch (Platform.operatingSystem) {
//       case 'windows':
//         return 'exe/win';
//       case 'macos':
//         return 'exe/mac';
//       default:
//         return 'exe/linux';
//     }
//   }

//   /// Replaces the old `rush.exe` with new one on Windows.
//   Future<void> _swapExe(String binDir) async {
//     final ext = Platform.isWindows ? '.exe' : '';

//     final old = File(p.join(binDir, 'rush' + ext));
//     final _new = File(p.join(binDir, 'rush' + ext + '.new'));

//     if (Platform.isWindows) {
//       // Replace old swap.exe with new if it exists.
//       final newSwap = p.join(binDir, 'swap.exe.new');
//       if (await File(newSwap).exists()) {
//         final oldSwap = File(p.join(binDir, 'swap.exe'));
//         await oldSwap.create();
//         await oldSwap.delete();
//         await File(newSwap).rename(oldSwap.path);
//       }

//       // TODO: Previously, this was using the ProcessRunner package, check if
//       // it still works.
//       await Process.start('swap.exe', ['-o', old.path],
//           mode: ProcessStartMode.detached);
//     } else {
//       await old.delete();
//       await _new.rename(old.path);
//       await _chmodExe(old.path);
//     }
//   }

//   /// Returns a [GhRelease] containing the information of the latest `rush-cli`
//   /// repo's release on GitHub.
//   Future<GhRelease> _fetchLatestRelease() async {
//     final Response response;
//     try {
//       response = await Dio().get('$_endpt/release');
//     } catch (e) {
//       Logger.log(LogType.erro, 'Something went wrong:');
//       Logger.log(LogType.erro, e.toString(), addPrefix: false);
//       exit(1);
//     }

//     final json = response.data as Map<String, dynamic>;
//     return GhRelease.fromJson(json);
//   }

//   /// Updates init box's values.
//   Future<void> _updateInitBox(
//       Box initBox, RepoContent content, String savePath) async {
//     final value = {
//       'path': savePath,
//       'sha': content.sha!,
//     };

//     await initBox.put(content.name, value);
//   }

//   /// Grants Rush binary execution permission on Unix systems.
//   Future<void> _chmodExe(String exePath) async {
//     await Process.run('chmod', ['+x', exePath]);
//   }
// }
