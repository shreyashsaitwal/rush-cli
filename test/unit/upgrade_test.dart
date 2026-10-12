import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;
import 'package:rush/src/commands/upgrade/upgrade.dart';
import 'package:test/test.dart';

void main() {
  late Directory rushHome;
  late String archive;
  final exe = Platform.isWindows ? 'rush.exe' : 'rush';

  setUp(() async {
    rushHome = await Directory.systemTemp.createTemp('rush-upgrade-');
    File(p.join(rushHome.path, 'bin', exe))
      ..createSync(recursive: true)
      ..writeAsStringSync('old');
    archive = p.join(rushHome.path, 'release.zip');
    final release = Archive()
      ..add(ArchiveFile.string('bin/$exe', 'new'))
      ..add(ArchiveFile.string('libs/processor.jar', 'jar'));
    File(archive).writeAsBytesSync(ZipEncoder().encodeBytes(release));
  });

  tearDown(() => rushHome.delete(recursive: true));

  test('installs every file of the release into the Rush home', () async {
    await installArchive(archive, rushHome);

    final installedExe = File(p.join(rushHome.path, 'bin', exe));
    expect(installedExe.readAsStringSync(), 'new');
    expect(File(p.join(rushHome.path, 'libs', 'processor.jar')).existsSync(),
        isTrue);
    expect(File('${installedExe.path}.new').existsSync(), isFalse);
    if (!Platform.isWindows) {
      expect(installedExe.statSync().mode & 0x49, 0x49);
    }
  });

  test('replaces the executable again on the next upgrade', () async {
    await installArchive(archive, rushHome);
    await installArchive(archive, rushHome);

    expect(File(p.join(rushHome.path, 'bin', exe)).readAsStringSync(), 'new');
  });
}
