@Timeout(Duration(minutes: 3))
library;

import 'dart:convert';

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

    test('is desugared again only when the dependencies change', () async {
      final desugared = project.file(
          '.rush/build/files/desugared-aars/androidx.core-core-ktx-1.5.0.aar.jar');
      final firstBuild = desugared.lastModifiedSync();
      expect((await project.build()).exitCode, 0);
      expect(desugared.lastModifiedSync(), firstBuild);

      project.addDependencies(['com.google.code.gson:gson:2.8.9']);
      final result = await project.build();
      expect(result.exitCode, 0, reason: result.output);
      expect(desugared.lastModifiedSync(), isNot(firstBuild));
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
}
