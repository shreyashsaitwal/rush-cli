@Timeout(Duration(minutes: 3))
library;

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
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
    expect(project.aix.classNames, isNot(contains('module-info.class')));
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

  test(
      'bundled libraries may contain classes of App Inventor libraries '
      'that only some apps include', () async {
    final project = await TestProject.create('zxing_ext');
    project.addDependencies(['com.google.zxing:core:3.5.3']);
    project.writeJavaExtension('''
  @SimpleFunction
  public String Writer() {
    return new com.google.zxing.qrcode.QRCodeWriter().toString();
  }
''');
    final result = await project.build(['--optimize']);
    expect(result.exitCode, 0, reason: result.output);
    expect(
        project.aix.classNames.where((c) => c.startsWith('com/google/zxing/')),
        isEmpty);
  });

  test('bundled libraries keep serializers looked up by reflection', () async {
    final project =
        await TestProject.create('serializers_ext', language: 'kotlin');
    project.addDependencies(
        ['org.jetbrains.kotlinx:kotlinx-serialization-json-jvm:1.11.0']);
    project.writeSource('${project.className}.kt', '''
package {package}

import com.google.appinventor.components.annotations.Extension
import com.google.appinventor.components.annotations.SimpleFunction
import com.google.appinventor.components.runtime.AndroidNonvisibleComponent
import com.google.appinventor.components.runtime.ComponentContainer
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.serializer

@Extension(description = "Encodes JSON.", icon = "icon.png")
class {className}(container: ComponentContainer) :
    AndroidNonvisibleComponent(container.`\$form`()) {

  @SimpleFunction(description = "Encodes a JSON array.")
  fun Encode(): String =
      Json.encodeToString(serializer<JsonArray>(), JsonArray(listOf(JsonPrimitive(1))))
}
''');
    final build = await project.build();
    expect(build.exitCode, 0, reason: build.output);
    expect(
        project.aix.methodNames('${project.packagePath}/repacked/'
            'kotlinx/serialization/json/JsonArray\$Companion'),
        contains('serializer'));
  });

  test('optimized builds write the mapping of renamed classes', () async {
    final project = await TestProject.create('mapping_ext');
    final mapping = project.file('out/${project.package}.mapping.txt');

    final optimized = await project.build(['--optimize']);
    expect(optimized.exitCode, 0, reason: optimized.output);
    expect(mapping.readAsStringSync(),
        contains('${project.package}.${project.className} ->'));

    final plain = await project.build();
    expect(plain.exitCode, 0, reason: plain.output);
    expect(mapping.existsSync(), isFalse);
  });

  test('Kotlin extensions can opt in to experimental APIs', () async {
    final project = await TestProject.create('opt_in_ext', language: 'kotlin');
    project.writeSource('${project.className}.kt', '''
package {package}

import androidx.annotation.OptIn
import androidx.annotation.RequiresOptIn
import com.google.appinventor.components.annotations.Extension
import com.google.appinventor.components.annotations.SimpleFunction
import com.google.appinventor.components.runtime.AndroidNonvisibleComponent
import com.google.appinventor.components.runtime.ComponentContainer

@RequiresOptIn
annotation class Experimental

@Extension(description = "Opts in.", icon = "icon.png")
class {className}(container: ComponentContainer) :
    AndroidNonvisibleComponent(container.`\$form`()) {

  @OptIn(markerClass = [Experimental::class])
  @SimpleFunction(description = "Returns one.")
  fun One(): Int = 1
}
''');
    for (final args in [
      <String>[],
      ['--optimize']
    ]) {
      final build = await project.build(args);
      expect(build.exitCode, 0, reason: build.output);
    }
  });

  group('an excluded library', () {
    late TestProject project;
    late ProcessResult build;

    setUpAll(() async {
      project = await TestProject.create('excluded_ext');
      project.addDependencies(['com.google.guava:guava:33.3.1-android']);
      project.placeLibraries({
        'com.google.guava:failureaccess': 'exclude',
        'com.example:nothing': 'exclude',
      });
      build = await project.build();
      if (build.exitCode != 0) fail(build.output);
    });

    test('is not resolved', () async {
      final tree = await project.depsTree();
      expect(tree.output,
          contains('com.google.guava:guava:33.3.1-android (private: jar)'));
      expect(
          tree.output,
          contains('Excluded in rush.yml: com.google.guava:failureaccess, '
              'com.example:nothing'));
      expect(tree.output, isNot(contains('failureaccess:')));
      expect(
          Directory(p.join(project.dir.path, '.idea', 'libraries'))
              .listSync()
              .map((el) => p.basename(el.path)),
          allOf(contains('com_google_guava_guava_33_3_1-android.xml'),
              isNot(anyElement(contains('failureaccess')))));
    });

    test('warns when it matches no library', () {
      expect(
          build.output,
          allOf(
              contains('com.example:nothing'), contains('matches no library')));
    });
  });

  group('a provided library', () {
    late TestProject project;

    setUpAll(() async {
      project = await TestProject.create('provided_ext');
      project.addDependencies(['com.google.guava:guava:33.3.1-android']);
      project.placeLibraries({'com.google.guava:guava': 'provided'});
      project.writeJavaExtension('''
  @SimpleFunction
  public String Blank(String text) {
    return com.google.common.base.Strings.nullToEmpty(text);
  }
''');
      final build = await project.build(['--optimize']);
      if (build.exitCode != 0) fail(build.output);
    });

    test('is compiled against but not shipped, nor what only it needs', () {
      expect(project.aix.classNames.where((c) => c.contains('com/google/')),
          isEmpty);
      expect(project.aix.libraries, isEmpty);
    });

    test('can still be listed in provided_dependencies, with a warning',
        () async {
      final legacy = await TestProject.create('legacy_provided_ext');
      legacy.editConfig('#license: LICENSE.txt',
          'provided_dependencies:\n- com.google.guava:guava:33.3.1-android');
      legacy.writeJavaExtension('''
  @SimpleFunction
  public String Blank(String text) {
    return com.google.common.base.Strings.nullToEmpty(text);
  }
''');
      final build = await legacy.build(['--optimize']);
      expect(build.exitCode, 0, reason: build.output);
      expect(build.output,
          allOf(contains('provided_dependencies'), contains('deprecated')));
      expect(legacy.aix.classNames.where((c) => c.contains('com/google/')),
          isEmpty);
    });

    test('is shown as provided with what only it needs', () async {
      final tree = (await project.depsTree()).output;
      expect(
          tree,
          contains(
              'com.google.guava:guava:33.3.1-android (provided: rush.yml)'));
      expect(
          tree,
          contains('com.google.guava:failureaccess:1.0.2 '
              '(provided: only provided libraries need it)'));
    });
  });

  group('libraries placed in rush.yml', () {
    test('ship as AARs when shared', () async {
      final project = await TestProject.create('shared_jar_ext');
      project.addDependencies(['com.google.code.gson:gson:2.8.9']);
      project.placeLibraries({'com.google.code.gson:gson': 'shared'});
      final build = await project.build();
      expect(build.exitCode, 0, reason: build.output);
      expect(project.aix.libraries, ['com.google.code.gson-gson-2.8.9.aar']);
    });

    test('move into the extension when private, keeping their manifest',
        () async {
      final project = await TestProject.create('private_aar_ext');
      project.file('deps/vibrate.aar')
        ..createSync(recursive: true)
        ..writeAsBytesSync(ZipEncoder().encode(Archive()
          ..addFile(ArchiveFile.string(
              'AndroidManifest.xml',
              '<manifest xmlns:android="http://schemas.android.com/apk/res/'
                  'android" package="com.example.vibrate"><uses-permission '
                  'android:name="android.permission.VIBRATE"/></manifest>'))
          ..addFile(ArchiveFile.bytes(
              'classes.jar', ZipEncoder().encode(Archive())))));
      project.addDependencies(['vibrate.aar']);
      project.placeLibraries({'vibrate.aar': 'private'});
      final build = await project.build();
      expect(build.exitCode, 0, reason: build.output);
      expect(project.aix.libraries, isEmpty);
      expect(jsonEncode(project.aix.buildInfo),
          contains('android.permission.VIBRATE'));
    });

    test('are refused as private when their resources would be left out',
        () async {
      final project = await TestProject.create('private_res_ext');
      project.addDependencies(['androidx.cardview:cardview:1.0.0']);
      project.placeLibraries({'androidx.cardview:cardview': 'private'});
      final build = await project.build();
      expect(build.exitCode, 1, reason: build.output);
      expect(
          build.output,
          contains("androidx.cardview:cardview:1.0.0 can't be private: its "
              'Android resources would be left out'));
    });

    test('are refused as private when a shared library uses them', () async {
      final project = await TestProject.create('private_used_ext');
      project.addDependencies(['androidx.media3:media3-common:1.11.1']);
      project.setMinSdk(23);
      project.placeLibraries({'com.google.guava:guava': 'private'});
      final build = await project.build();
      expect(build.exitCode, 1, reason: build.output);
      expect(
          build.output,
          contains("com.google.guava:guava:33.3.1-android can't be private: "
              'androidx.media3:media3-common:1.11.1 ships unchanged'));
    });
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
