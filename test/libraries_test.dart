@Timeout(Duration(minutes: 3))
library;

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:test/test.dart';

import 'support/aix.dart';
import 'support/fixtures.dart';
import 'support/project.dart';

void main() {
  group('the Kotlin standard library', () {
    late TestProject project;
    late Aix aix;

    setUpAll(() async {
      project = await TestProject.create('kotlin_ext', language: 'kotlin');
      project.writeHelperEnum();
      final result = await project.build();
      if (result.exitCode != 0) fail(result.output);
      aix = project.aix;
    });

    test('moves under the extension package when only it uses it', () {
      expect(aix.classNames,
          anyElement(startsWith('${project.packagePath}/repacked/kotlin/')));
      expect(aix.classNames.where((c) => c.startsWith('kotlin/')), isEmpty);
    });

    test('shrinks to what the extension uses', () {
      final stdlib = aix.classNames.where(
          (c) => c.startsWith('${project.packagePath}/repacked/kotlin/'));
      expect(stdlib.length, lessThan(100));
      expect(aix.classNames, contains(project.classFile('helpers/Mode')));
    });
  });

  group('an AAR dependency', () {
    late TestProject project;

    setUpAll(() async {
      project = await TestProject.create('core_aar_ext');
      project.addDependencies(['androidx.core:core-ktx:1.5.0']);
      final result = await project.build();
      if (result.exitCode != 0) fail(result.output);
    });

    test('is desugared again only when its classpath changes', () async {
      const desugaring = 'Desugaring androidx.core-core-ktx-1.5.0.aar';
      project.file('deps/stamp.jar').writeAsBytesSync(ZipEncoder().encode(
          Archive()
            ..addFile(ArchiveFile.string(
                'stamp.txt', '${DateTime.now().microsecondsSinceEpoch}'))));
      project.addDependencies(['stamp.jar']);
      final changed = await project.build();
      expect(changed.exitCode, 0, reason: changed.output);
      expect(changed.output, contains(desugaring));

      final unchanged = await project.build();
      expect(unchanged.exitCode, 0, reason: unchanged.output);
      expect(unchanged.output, isNot(contains(desugaring)));

      await rush(['clean'], workingDirectory: project.dir.path);
      final cleaned = await project.build();
      expect(cleaned.exitCode, 0, reason: cleaned.output);
      expect(cleaned.output, isNot(contains(desugaring)));
    });

    test('warns when it is both local and remote', () async {
      project.file('deps/core-ktx-local.aar').writeAsBytesSync(ZipEncoder()
          .encode(project.aix.library('androidx.core-core-ktx-1.5.0.aar')));
      project.addDependencies(['core-ktx-local.aar']);

      final result = await project.build();
      expect(result.exitCode, 0, reason: result.output);
      expect(
          result.output,
          contains(
              'androidx.core:core-ktx:1.5.0 and core-ktx-local.aar are the same library'));
    });
  });

  test('bundled libraries keep what their ProGuard rules keep', () async {
    final project = await TestProject.create('rules_ext');
    project.addDependencies(['com.google.code.gson:gson:2.8.9']);
    final parser =
        '${project.packagePath}/repacked/com/google/gson/JsonParser.class';
    final unruled = await project.build();
    expect(unruled.exitCode, 0, reason: unruled.output);
    expect(project.aix.classNames, isNot(contains(parser)));

    final rules = Archive()
      ..addFile(ArchiveFile.string('META-INF/proguard/keep.pro',
          '-keep class com.google.gson.JsonParser'));
    project
        .file('deps/keep-rules.jar')
        .writeAsBytesSync(ZipEncoder().encode(rules));
    project.addDependencies(['keep-rules.jar']);
    final ruled = await project.build();
    expect(ruled.exitCode, 0, reason: ruled.output);
    expect(project.aix.classNames, contains(parser));
  });

  test('bundled libraries ship as AARs when a bundled AAR depends on them',
      () async {
    final project = await TestProject.create('media_ext');
    project.addDependencies(['androidx.media3:media3-common:1.11.1']);
    project.setMinSdk(23);
    final result = await project.build();
    expect(result.exitCode, 0, reason: result.output);

    final aix = project.aix;
    const guava = 'com.google.guava-guava-33.3.1-android.aar';
    expect(aix.libraries, contains(guava));
    expect(
        utf8.decode(
            aix.library(guava).findFile('AndroidManifest.xml')!.content),
        contains('package="com.google.guava.guava"'));
    expect(
        aix.classNames.where((c) => c.contains('com/google/common/')), isEmpty);
  });

  group('fonts in shipped AARs', () {
    late TestProject project;
    late ProcessResult build;
    late Aix aix;

    String text(Archive archive, String name) =>
        utf8.decode(archive.findFile(name)!.content);

    Set<String> classNames(Archive aar) => {
          for (final file in ZipDecoder()
              .decodeBytes(aar.findFile('classes.jar')!.content)
              .files)
            file.name,
        };

    setUpAll(() async {
      project = await TestProject.create('fonts_ext');
      project.setMinSdk(26);
      project
          .addDependencies(['androidx.media3:media3-ui:1.11.1', 'player.aar']);
      project.file('deps/player.aar').writeAsBytesSync(ZipEncoder().encode(
          Archive()
            ..addFile(ArchiveFile.string('AndroidManifest.xml',
                '<manifest package="com.example.player"/>'))
            ..addFile(ArchiveFile.string(
                'R.txt', 'int font roboto_medium_numbers 0x7f010001\n'))
            ..addFile(ArchiveFile.string(
                'res/values/styles.xml',
                '<resources><style name="player_time"><item '
                    'name="android:fontFamily">@font/roboto_medium_numbers'
                    '</item></style></resources>'))
            ..addFile(ArchiveFile.bytes(
                'classes.jar', ZipEncoder().encode(Archive())))));
      project.file('res/font/com_example_fontsext_numbers.ttf')
        ..createSync(recursive: true)
        ..writeAsBytesSync(File(
                'tool/e2e/fixtures/fonts/res/font/com_example_fonts_numbers.ttf')
            .readAsBytesSync());
      project.writeJavaExtension('''
  @SimpleFunction
  public int Numbers() {
    return R.font.com_example_fontsext_numbers;
  }
''');
      build = await project.build();
      if (build.exitCode != 0) fail(build.output);
      aix = project.aix;
    });

    test('move to res/raw with their symbols retyped', () {
      final ui = aix.library('androidx.media3-media3-ui-1.11.1.aar');
      expect(ui.findFile('res/raw/roboto_medium_numbers.ttf'), isNotNull);
      expect(ui.files.where((el) => el.name.startsWith('res/font')), isEmpty);
      expect(text(ui, 'R.txt'), contains('int raw roboto_medium_numbers '));
      expect(text(ui, 'R.txt'), isNot(contains('int font ')));
    });

    test('are referenced as raw resources by dependent AARs', () {
      final player = aix.library('player.aar');
      expect(text(player, 'res/values/styles.xml'),
          contains('@raw/roboto_medium_numbers'));
      expect(
          text(player, 'R.txt'), 'int raw roboto_medium_numbers 0x7f010001\n');
    });

    test('stay reachable through R.font', () {
      expect(classNames(aix.library('androidx.media3-media3-ui-1.11.1.aar')),
          contains(r'androidx/media3/ui/R$font.class'));
      expect(classNames(aix.library('player.aar')),
          contains(r'com/example/player/R$font.class'));
      expect(classNames(aix.library('com.example.fontsext.aar')),
          contains(r'com/example/fontsext/R$font.class'));
    });

    test('include the extension own fonts', () {
      final own = aix.library('com.example.fontsext.aar');
      expect(
          own.findFile('res/raw/com_example_fontsext_numbers.ttf'), isNotNull);
      expect(text(own, 'R.txt'),
          contains('int raw com_example_fontsext_numbers '));
    });

    test('are reported in the build output', () {
      expect(build.output,
          contains('Moved fonts to res/raw so Kodular can build'));
    });
  });
}
