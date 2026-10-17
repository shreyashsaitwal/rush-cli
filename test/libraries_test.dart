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

Future<Map<String, List<int>>> _compiled(
    TestProject project, Map<String, String> sources) async {
  final sourceDir = p.join(project.dir.path, 'library-src');
  final classesDir = p.join(project.dir.path, 'library-classes');
  final files = [
    for (final MapEntry(key: name, value: source) in sources.entries)
      File(p.join(sourceDir, '$name.java'))
        ..createSync(recursive: true)
        ..writeAsStringSync(source),
  ];
  final javac = await Process.run('javac', [
    '--release',
    '8',
    '-d',
    classesDir,
    for (final file in files) file.path
  ]);
  expect(javac.exitCode, 0, reason: '${javac.stderr}');
  return {
    for (final file
        in Directory(classesDir).listSync(recursive: true).whereType<File>())
      p.posix.joinAll(p.split(p.relative(file.path, from: classesDir))):
          file.readAsBytesSync(),
  };
}

final _javapFields = RegExp(
    r'^  (\S.*);\n    descriptor: [^(].*\n    flags: \(0x[0-9a-f]+\) (.*)$',
    multiLine: true);

List<int> _jar(Map<String, List<int>> entries) {
  final archive = Archive();
  for (final MapEntry(key: name, value: bytes) in entries.entries) {
    archive.addFile(ArchiveFile.bytes(name, bytes));
  }
  return ZipEncoder().encode(archive);
}

void _writeAar(
        TestProject project, String name, Map<String, List<int>> entries) =>
    project.file('deps/$name')
      ..createSync(recursive: true)
      ..writeAsBytesSync(_jar(entries));

List<String> _classesOf(Archive aar) => ZipDecoder()
    .decodeBytes(aar.findFile('classes.jar')!.content)
    .files
    .where((el) => el.isFile)
    .map((el) => el.name)
    .toList();

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

    test('keeps Kotlin\'s null checks', () {
      expect(
          aix.classNames,
          contains(
              '${project.packagePath}/repacked/kotlin/jvm/internal/Intrinsics.class'));
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
      project.placeLibraries({'androidx.core:core-ktx': 'shared'});
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

  test('bundled libraries ship as AARs when a shared AAR depends on them',
      () async {
    final project = await TestProject.create('media_ext');
    project.addDependencies(['androidx.media3:media3-common:1.11.1']);
    project.placeLibraries({'androidx.media3:media3-common': 'shared'});
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

  test('bundled libraries that use missing classes fail until rules allow it',
      () async {
    final project = await TestProject.create('missing_class_ext');
    final sources = Directory(p.join(project.dir.path, 'library-src'));
    File(p.join(sources.path, 'optional', 'Plugin.java'))
      ..createSync(recursive: true)
      ..writeAsStringSync('package optional; public class Plugin {}');
    File(p.join(sources.path, 'library', 'Loader.java'))
      ..createSync(recursive: true)
      ..writeAsStringSync('package library; public class Loader { '
          'public static Object load() { return new optional.Plugin(); } }');
    final classes = p.join(project.dir.path, 'library-classes');
    final javac = await Process.run('javac', [
      '-d',
      classes,
      p.join(sources.path, 'optional', 'Plugin.java'),
      p.join(sources.path, 'library', 'Loader.java'),
    ]);
    expect(javac.exitCode, 0, reason: '${javac.stderr}');
    final loader = File(p.join(classes, 'library', 'Loader.class'));
    project.file('deps/loader.jar')
      ..createSync(recursive: true)
      ..writeAsBytesSync(ZipEncoder().encode(Archive()
        ..addFile(ArchiveFile.bytes(
            'library/Loader.class', loader.readAsBytesSync()))));
    project.addDependencies(['loader.jar']);
    project.writeJavaExtension('''
  @SimpleFunction
  public String Load() {
    return String.valueOf(library.Loader.load());
  }
''');

    final missing = await project.build();
    expect(missing.exitCode, 1, reason: missing.output);
    expect(missing.output,
        allOf(contains('optional.Plugin'), contains('-dontwarn')));

    final rules = project.file('src/proguard-rules.pro');
    rules.writeAsStringSync(
        '${rules.readAsStringSync()}\n-dontwarn optional.**\n');
    final allowed = await project.build();
    expect(allowed.exitCode, 0, reason: allowed.output);
  });

  test('libraries missing classes from older provided ones name the rule',
      () async {
    final project = await TestProject.create('older_annotation_ext');
    final classes = await _compiled(project, {
      'androidx/annotation/DoNotInline':
          'package androidx.annotation; public @interface DoNotInline {}',
      'com/example/util/Clock': 'package com.example.util; '
          'public class Clock { @androidx.annotation.DoNotInline '
          'public static long now() { return 1L; } }',
    });
    project.file('deps/clock.jar')
      ..createSync(recursive: true)
      ..writeAsBytesSync(_jar({
        'com/example/util/Clock.class':
            classes['com/example/util/Clock.class']!,
      }));
    project.addDependencies(['clock.jar']);
    project.writeJavaExtension('''
  @SimpleFunction
  public long Now() {
    return com.example.util.Clock.now();
  }
''');
    final rules = project.file('src/proguard-rules.pro');
    rules.writeAsStringSync(rules
        .readAsStringSync()
        .replaceFirst('-dontwarn androidx.annotation.**', ''));

    final build = await project.build();
    expect(build.exitCode, 1, reason: build.output);
    expect(
        build.output,
        allOf(
            contains('androidx.annotation.DoNotInline is missing from '
                'androidx.annotation:annotation:'),
            contains('add `-dontwarn androidx.annotation.DoNotInline`')));
  });

  test('App Inventor\'s libraries stand in for their multiplatform variants',
      () async {
    final project = await TestProject.create('variants_ext');
    project
        .addDependencies(['androidx.datastore:datastore-core-android:1.1.7']);
    project.placeLibraries(
        {'androidx.datastore:datastore-core-android': 'shared'});
    project.setMinSdk(24);

    final build = await project.build();
    expect(build.exitCode, 0, reason: build.output);
    expect(
        project.aix.libraries, isNot(anyElement(contains('annotation-jvm'))));
    expect(
        build.output,
        contains('androidx.annotation:annotation-jvm:1.7.0 is required, but '
            'App Inventor provides an older version'));
  });

  test('desugared interfaces have fields every dex version accepts', () async {
    final project = await TestProject.create('interfaces_ext');
    project.setMinSdk(23);
    project.file('deps/factory.jar')
      ..createSync(recursive: true)
      ..writeAsBytesSync(_jar(await _compiled(project, {
        'com/example/factory/Factory': 'package com.example.factory; '
            'public interface Factory { '
            'Factory EMPTY = () -> new String[0]; '
            'String[] create(); '
            'default String[] create(String uri) { return create(); } }',
        'com/example/factory/Single': 'package com.example.factory; '
            'public class Single implements Factory { '
            'public String[] create() { return new String[] {"one"}; } }',
        'com/example/factory/Pair': 'package com.example.factory; '
            'public class Pair implements Factory { '
            'public String[] create() { return new String[] {"one", "two"}; } }',
      })));
    project.addDependencies(['factory.jar']);
    project.writeJavaExtension('''
  @SimpleFunction
  public int Count(String uri) {
    com.example.factory.Factory factory = uri.isEmpty()
        ? new com.example.factory.Single()
        : new com.example.factory.Pair();
    return factory.create(uri).length;
  }
''');

    final build = await project.build(['--optimize']);
    expect(build.exitCode, 0, reason: build.output);
    final bytes = project.aix.bytes('files/AndroidRuntime.jar');
    final runtime = p.join(project.dir.path, 'runtime.jar');
    File(runtime).writeAsBytesSync(bytes);
    final javap = await Process.run('javap', [
      '-p',
      '-v',
      '-cp',
      runtime,
      for (final file in ZipDecoder().decodeBytes(bytes))
        if (file.name.endsWith('.class'))
          file.name.substring(0, file.name.length - '.class'.length),
    ]);
    expect(javap.exitCode, 0, reason: '${javap.stderr}');
    final interfaceFields = [
      for (final type in (javap.stdout as String)
          .split(RegExp(r'^Classfile ', multiLine: true)))
        if (type
            .contains(RegExp(r'^  flags: .*ACC_INTERFACE', multiLine: true)))
          for (final field in _javapFields.allMatches(type))
            '${field[1]} ${field[2]}',
    ];
    expect(interfaceFields, contains(contains(r'$desugar$clinit')));
    expect(interfaceFields,
        everyElement(contains('ACC_PUBLIC, ACC_STATIC, ACC_FINAL')));
  });

  test('AARs without code are placed but add no code', () async {
    final project = await TestProject.create('codeless_ext');
    project.file('deps/umbrella.aar')
      ..createSync(recursive: true)
      ..writeAsBytesSync(_jar({
        'AndroidManifest.xml':
            utf8.encode('<manifest package="com.example.umbrella"/>'),
      }));
    project.addDependencies(['umbrella.aar']);

    final private = await project.build();
    expect(private.exitCode, 0, reason: private.output);
    expect(private.output, isNot(contains('non-existent location')));

    project.placeLibraries({'umbrella.aar': 'shared'});
    final shared = await project.build();
    expect(shared.exitCode, 0, reason: shared.output);
    expect(project.aix.library('umbrella.aar').findFile('classes.jar'), isNull);
  });

  test('private AARs are renamed into the extension', () async {
    final project = await TestProject.create('private_aar_ext');
    final classes = await _compiled(project, {
      'com/example/player/R':
          'package com.example.player; public final class R { '
              'public static final class drawable { public static int play; } }',
      'com/example/player/PlaybackService': 'package com.example.player; '
          'public class PlaybackService { '
          'public static int icon() { return R.drawable.play; } }',
      'com/example/player/TimeBar':
          'package com.example.player; public class TimeBar {}',
    });
    final classesJar = _jar({
      for (final name in ['PlaybackService', 'TimeBar'])
        'com/example/player/$name.class':
            classes['com/example/player/$name.class']!,
    });
    project.file('deps/player.aar')
      ..createSync(recursive: true)
      ..writeAsBytesSync(ZipEncoder().encode(Archive()
        ..addFile(ArchiveFile.string(
            'AndroidManifest.xml',
            '<manifest xmlns:android="http://schemas.android.com/apk/res/'
                'android" package="com.example.player"><application>'
                '<service android:name="com.example.player.PlaybackService" '
                'android:icon="@drawable/play"/></application></manifest>'))
        ..addFile(ArchiveFile.string('res/drawable/play.xml', '<vector/>'))
        ..addFile(ArchiveFile.string(
            'res/layout/controls.xml', '<com.example.player.TimeBar/>'))
        ..addFile(ArchiveFile.string(
            'R.txt', 'int drawable play 0x0\nint layout controls 0x0\n'))
        ..addFile(ArchiveFile.bytes('classes.jar', classesJar))));
    project.addDependencies(['player.aar']);
    project.placeLibraries({'player.aar': 'private'});
    project.writeJavaExtension('''
  @SimpleFunction
  public int Icon() {
    return com.example.player.PlaybackService.icon();
  }
''');

    final build = await project.build();
    expect(build.exitCode, 0, reason: build.output);
    final renamed = '${project.package}.repacked';
    final prefix = '${project.package.replaceAll('.', '_')}_repacked_';
    final aix = project.aix;
    expect(aix.libraries, ['$renamed.player.aar']);
    final aar = aix.library('$renamed.player.aar');
    String text(String name) => utf8.decode(aar.findFile(name)!.content);
    expect(
        text('AndroidManifest.xml'),
        allOf(
            contains('package="$renamed.com.example.player"'),
            contains('android:name="$renamed.com.example.player.'
                'PlaybackService"'),
            contains('android:icon="@drawable/${prefix}play"')));
    expect(text('res/drawable/${prefix}play.xml'), '<vector/>');
    expect(text('res/layout/${prefix}controls.xml'),
        '<$renamed.com.example.player.TimeBar/>');
    expect(text('R.txt'), contains('int drawable ${prefix}play 0x0'));
    expect(
        ZipDecoder()
            .decodeBytes(aar.findFile('classes.jar')!.content)
            .files
            .map((el) => el.name),
        containsAll([
          '${project.packagePath}/repacked/com/example/player/PlaybackService.class',
          '${project.packagePath}/repacked/com/example/player/TimeBar.class',
        ]));
    expect(jsonEncode(aix.buildInfo['activities']),
        contains('$renamed.com.example.player.PlaybackService'));
  });

  test('private AARs keep the private code they use', () async {
    final project = await TestProject.create('private_user_ext');
    final classes = await _compiled(project, {
      'com/example/util/Formatter': 'package com.example.util; '
          'public class Formatter { '
          'public static String format(int value) { return "#" + value; } }',
      'com/example/player/R':
          'package com.example.player; public final class R { '
              'public static final class drawable { public static int play; } }',
      'com/example/player/Label': 'package com.example.player; '
          'public class Label { public static String text() { '
          'return com.example.util.Formatter.format(R.drawable.play); } }',
    });
    project.file('deps/util.jar')
      ..createSync(recursive: true)
      ..writeAsBytesSync(_jar({
        'com/example/util/Formatter.class':
            classes['com/example/util/Formatter.class']!,
      }));
    project.file('deps/player.aar')
      ..createSync(recursive: true)
      ..writeAsBytesSync(ZipEncoder().encode(Archive()
        ..addFile(ArchiveFile.string(
            'AndroidManifest.xml', '<manifest package="com.example.player"/>'))
        ..addFile(ArchiveFile.string('res/drawable/play.xml', '<vector/>'))
        ..addFile(ArchiveFile.string('R.txt', 'int drawable play 0x0\n'))
        ..addFile(ArchiveFile.bytes(
            'classes.jar',
            _jar({
              'com/example/player/Label.class':
                  classes['com/example/player/Label.class']!,
            })))));
    project.addDependencies(['util.jar', 'player.aar']);
    project.placeLibraries({'util.jar': 'private', 'player.aar': 'private'});
    project.writeJavaExtension('''
  @SimpleFunction
  public String Label() {
    return com.example.player.Label.text();
  }
''');

    final build = await project.build();
    expect(build.exitCode, 0, reason: build.output);
    expect(
        project.aix.classNames,
        contains(
            '${project.packagePath}/repacked/com/example/util/Formatter.class'));
  });

  test('private libraries rename strings naming their removed classes',
      () async {
    final project = await TestProject.create('private_strings_ext');
    final classes = await _compiled(project, {
      'com/example/util/Plugins': 'package com.example.util; '
          'public class Plugins { public static String name() { '
          'return "com.example.util.Missing"; } }',
      'com/example/util/Missing':
          'package com.example.util; public class Missing {}',
    });
    project.file('deps/util.jar')
      ..createSync(recursive: true)
      ..writeAsBytesSync(_jar(classes));
    project.addDependencies(['util.jar']);
    project.placeLibraries({'util.jar': 'private'});
    project.writeJavaExtension('''
  @SimpleFunction
  public String Plugin() {
    return com.example.util.Plugins.name();
  }
''');

    final build = await project.build();
    expect(build.exitCode, 0, reason: build.output);
    final runtime = ZipDecoder()
        .decodeBytes(project.aix.bytes('files/AndroidRuntime.jar'))
        .files
        .map((el) => latin1.decode(el.content))
        .join();
    expect(runtime,
        contains('${project.package}.repacked.com.example.util.Missing'));
  });

  test('optimized builds resolve service lookups of private libraries',
      () async {
    final project = await TestProject.create('private_services_ext');
    final classes = await _compiled(project, {
      'com/example/greet/Greeter': 'package com.example.greet; '
          'public interface Greeter { String greet(); }',
      'com/example/greet/English': 'package com.example.greet; '
          'public class English implements Greeter { '
          'public String greet() { return "hello"; } }',
    });
    project.file('deps/greet.jar')
      ..createSync(recursive: true)
      ..writeAsBytesSync(_jar({
        ...classes,
        'META-INF/services/com.example.greet.Greeter':
            utf8.encode('com.example.greet.English\n'),
      }));
    project.addDependencies(['greet.jar']);
    project.placeLibraries({'greet.jar': 'private'});
    project.writeJavaExtension('''
  @SimpleFunction
  public String Greet() {
    return java.util.ServiceLoader.load(com.example.greet.Greeter.class,
        com.example.greet.Greeter.class.getClassLoader())
        .iterator().next().greet();
  }
''');

    final build = await project.build(['--optimize']);
    expect(build.exitCode, 0, reason: build.output);
    final runtime = ZipDecoder()
        .decodeBytes(project.aix.bytes('files/AndroidRuntime.jar'))
        .files
        .map((el) => latin1.decode(el.content))
        .join();
    expect(runtime,
        allOf(contains('hello'), isNot(contains('java/util/ServiceLoader'))));
  });

  test('private libraries keep intent actions named like their classes',
      () async {
    final project = await TestProject.create('private_action_ext');
    final classes = await _compiled(project, {
      'com/example/player/PlaybackService': 'package com.example.player; '
          'public class PlaybackService { public static String action() { '
          'return "com.example.player.PlaybackService"; } }',
    });
    _writeAar(project, 'player.aar', {
      'AndroidManifest.xml':
          utf8.encode('<manifest package="com.example.player"/>'),
      'res/drawable/play.xml': utf8.encode('<vector/>'),
      'R.txt': utf8.encode('int drawable play 0x0\n'),
      'classes.jar': _jar(classes),
    });
    project.addDependencies(['player.aar']);
    project.writeJavaExtension('''
  @SimpleFunction
  public String Action() {
    return com.example.player.PlaybackService.action();
  }
''');
    final manifest = project.file('src/AndroidManifest.xml');
    manifest.writeAsStringSync(manifest.readAsStringSync().replaceFirst(
        '<application>',
        '<application><service android:name="com.example.Playback">'
            '<intent-filter><action '
            'android:name="com.example.player.PlaybackService"/>'
            '</intent-filter></service>'));

    final build = await project.build();
    expect(build.exitCode, 0, reason: build.output);
    final renamed = '${project.package}.repacked.com.example.player';
    expect(
        jsonEncode(project.aix.buildInfo['activities']),
        allOf(contains('com.example.player.PlaybackService'),
            isNot(contains('$renamed.PlaybackService'))));
    final code = [
      for (final file in ZipDecoder()
          .decodeBytes(project.aix
              .library('${project.package}.repacked.player.aar')
              .findFile('classes.jar')!
              .content)
          .files)
        latin1.decode(file.content),
    ].join();
    expect(
        code,
        allOf(contains('com.example.player.PlaybackService'),
            isNot(contains('$renamed.PlaybackService'))));
  });

  test('private libraries rename manifest values naming their classes',
      () async {
    final project = await TestProject.create('private_registrar_ext');
    final classes = await _compiled(project, {
      'com/example/components/ComponentRegistrar':
          'package com.example.components; '
              'public interface ComponentRegistrar {}',
      'com/example/components/Discovery': 'package com.example.components; '
          'public class Discovery { public static boolean registers('
          'String value) { return '
          '"com.example.components.ComponentRegistrar".equals(value); } }',
    });
    _writeAar(project, 'components.aar', {
      'AndroidManifest.xml': utf8
          .encode('<manifest xmlns:android="http://schemas.android.com/apk/res/'
              'android" package="com.example.components"><application>'
              '<service android:name="com.example.components.Discovery">'
              '<meta-data android:name="com.example.components:Registrar" '
              'android:value="com.example.components.ComponentRegistrar"/>'
              '</service></application></manifest>'),
      'classes.jar': _jar(classes),
    });
    project.addDependencies(['components.aar']);
    project.writeJavaExtension('''
  @SimpleFunction
  public boolean Registers(String value) {
    return com.example.components.Discovery.registers(value);
  }
''');

    final build = await project.build();
    expect(build.exitCode, 0, reason: build.output);
    final renamed =
        '${project.package}.repacked.com.example.components.ComponentRegistrar';
    expect(jsonEncode(project.aix.buildInfo['activities']),
        contains('android:value=\\"$renamed\\"'));
    final code = ZipDecoder()
        .decodeBytes(project.aix.bytes('files/AndroidRuntime.jar'))
        .files
        .map((el) => latin1.decode(el.content))
        .join();
    expect(code, contains(renamed));
  });

  test('private libraries switch on renamed class names', () async {
    final project = await TestProject.create('private_switch_ext');
    project.file('deps/util.jar')
      ..createSync(recursive: true)
      ..writeAsBytesSync(_jar(await _compiled(project, {
        'com/example/util/Plugin':
            'package com.example.util; public class Plugin {}',
        'com/example/util/Lookup': 'package com.example.util; '
            'public class Lookup { public static int find(String name) { '
            'switch (name) { case "com.example.util.Plugin": return 1; '
            'case "com.example.util.Other": return 2; default: return 0; '
            '} } }',
      })));
    project.addDependencies(['util.jar']);
    project.writeJavaExtension('''
  @SimpleFunction
  public int Find() {
    return com.example.util.Lookup.find(
        com.example.util.Plugin.class.getName());
  }
''');

    final build = await project.build();
    expect(build.exitCode, 0, reason: build.output);
    final lookup = ZipDecoder()
        .decodeBytes(project.aix.bytes('files/AndroidRuntime.jar'))
        .findFile(
            '${project.packagePath}/repacked/com/example/util/Lookup.class')!;
    expect(
        latin1.decode(lookup.content),
        allOf(contains('${project.package}.repacked.com.example.util.Plugin'),
            isNot(contains('hashCode'))));
  });

  test('private libraries keep intent actions the extension queries', () async {
    final project = await TestProject.create('private_query_ext');
    final classes = await _compiled(project, {
      'com/example/session/SessionService': 'package com.example.session; '
          'public class SessionService { public static String action() { '
          'return "com.example.session.SessionService"; } }',
    });
    project.file('deps/session.jar')
      ..createSync(recursive: true)
      ..writeAsBytesSync(_jar(classes));
    project.addDependencies(['session.jar']);
    project.writeJavaExtension('''
  @SimpleFunction
  public String Action() {
    return com.example.session.SessionService.action();
  }
''');
    final manifest = project.file('src/AndroidManifest.xml');
    manifest.writeAsStringSync(manifest.readAsStringSync().replaceFirst(
        '<application>',
        '<queries><intent><action '
            'android:name="com.example.session.SessionService"/>'
            '</intent></queries><application>'));

    final build = await project.build();
    expect(build.exitCode, 0, reason: build.output);
    final code = ZipDecoder()
        .decodeBytes(project.aix.bytes('files/AndroidRuntime.jar'))
        .files
        .map((el) => latin1.decode(el.content))
        .join();
    expect(
        code,
        allOf(
            contains('com.example.session.SessionService'),
            isNot(
                contains('${project.package}.repacked.com.example.session'))));
  });

  test('extension layouts use the renamed views of private libraries',
      () async {
    final project = await TestProject.create('private_view_ext');
    final classes = await _compiled(project, {
      'com/example/player/TimeBar':
          'package com.example.player; public class TimeBar {}',
    });
    _writeAar(project, 'player.aar', {
      'AndroidManifest.xml':
          utf8.encode('<manifest package="com.example.player"/>'),
      'res/drawable/play.xml': utf8.encode('<vector/>'),
      'R.txt': utf8.encode('int drawable play 0x0\n'),
      'classes.jar': _jar(classes),
    });
    project.addDependencies(['player.aar']);
    project.file('res/layout/com_example_privateviewext_bar.xml')
      ..createSync(recursive: true)
      ..writeAsStringSync('<com.example.player.TimeBar '
          'xmlns:android="http://schemas.android.com/apk/res/android" '
          'android:layout_width="match_parent" '
          'android:layout_height="wrap_content"/>');

    final build = await project.build();
    expect(build.exitCode, 0, reason: build.output);
    final renamed = '${project.package}.repacked.com.example.player.TimeBar';
    expect(
        utf8.decode(project.aix
            .library('${project.package}.aar')
            .findFile('res/layout/com_example_privateviewext_bar.xml')!
            .content),
        startsWith('<$renamed '));
    expect(
        _classesOf(
            project.aix.library('${project.package}.repacked.player.aar')),
        contains('${renamed.replaceAll('.', '/')}.class'));
  });

  test('private libraries use the R classes App Inventor generates', () async {
    final project = await TestProject.create('private_appcompat_ext');
    final classes = await _compiled(project, {
      'androidx/appcompat/R': 'package androidx.appcompat; public final class '
          'R { public static final class attr { public static int '
          'colorAccent; } }',
      'com/example/themed/Accent': 'package com.example.themed; '
          'public class Accent { public static int attr() { '
          'return androidx.appcompat.R.attr.colorAccent; } }',
    });
    project.file('deps/themed.jar')
      ..createSync(recursive: true)
      ..writeAsBytesSync(_jar({
        'com/example/themed/Accent.class':
            classes['com/example/themed/Accent.class']!,
      }));
    project.addDependencies(['themed.jar']);
    project.writeJavaExtension('''
  @SimpleFunction
  public int Accent() {
    return com.example.themed.Accent.attr();
  }
''');

    final build = await project.build();
    expect(build.exitCode, 0, reason: build.output);
  });

  test('private AARs ship only the code that is used or kept', () async {
    final project = await TestProject.create('private_shrunk_ext');
    final classes = await _compiled(project, {
      'com/example/player/Api': 'package com.example.player; '
          'public class Api { public static int version() { return 2; } }',
      'com/example/player/TimeBar':
          'package com.example.player; public class TimeBar {}',
      'com/example/player/Reflected':
          'package com.example.player; public class Reflected {}',
      'com/example/player/Unused':
          'package com.example.player; public class Unused {}',
    });
    _writeAar(project, 'player.aar', {
      'AndroidManifest.xml':
          utf8.encode('<manifest package="com.example.player"/>'),
      'res/layout/controls.xml': utf8.encode('<com.example.player.TimeBar/>'),
      'R.txt': utf8.encode('int layout controls 0x0\n'),
      'proguard.txt': utf8.encode('-keep class com.example.player.Reflected\n'),
      'classes.jar': _jar(classes),
    });
    project.addDependencies(['player.aar']);
    project.placeLibraries({'player.aar': 'private'});
    project.writeJavaExtension('''
  @SimpleFunction
  public int Version() {
    return com.example.player.Api.version();
  }
''');

    final build = await project.build();
    expect(build.exitCode, 0, reason: build.output);
    final renamed = '${project.packagePath}/repacked/com/example/player';
    expect(
        _classesOf(
            project.aix.library('${project.package}.repacked.player.aar')),
        unorderedEquals([
          '$renamed/Api.class',
          '$renamed/TimeBar.class',
          '$renamed/Reflected.class',
        ]));
  });

  test('private AARs implement default methods of private jars', () async {
    final project = await TestProject.create('private_defaults_ext');
    final classes = await _compiled(project, {
      'com/example/util/Greeter': 'package com.example.util; '
          'public interface Greeter { '
          'default String greet() { return "hi"; } }',
      'com/example/player/Friendly': 'package com.example.player; '
          'public class Friendly implements com.example.util.Greeter {}',
    });
    project.file('deps/util.jar')
      ..createSync(recursive: true)
      ..writeAsBytesSync(_jar({
        'com/example/util/Greeter.class':
            classes['com/example/util/Greeter.class']!,
      }));
    _writeAar(project, 'player.aar', {
      'AndroidManifest.xml':
          utf8.encode('<manifest package="com.example.player"/>'),
      'res/drawable/play.xml': utf8.encode('<vector/>'),
      'R.txt': utf8.encode('int drawable play 0x0\n'),
      'classes.jar': _jar({
        'com/example/player/Friendly.class':
            classes['com/example/player/Friendly.class']!,
      }),
    });
    project.addDependencies(['util.jar', 'player.aar']);
    project.placeLibraries({'util.jar': 'private', 'player.aar': 'private'});
    project.writeJavaExtension('''
  @SimpleFunction
  public String Greet() {
    return new com.example.player.Friendly().greet();
  }
''');

    final build = await project.build();
    expect(build.exitCode, 0, reason: build.output);
  });

  test('private AARs keep the attributes App Inventor\'s AndroidX defines',
      () async {
    final project = await TestProject.create('private_attrs_ext');
    _writeAar(project, 'chips.aar', {
      'AndroidManifest.xml':
          utf8.encode('<manifest package="com.example.chips"/>'),
      'res/values/values.xml': utf8.encode('<resources>'
          '<declare-styleable name="Chip">'
          '<attr name="icon" format="reference"/>'
          '<attr name="chipSize" format="dimension"/>'
          '</declare-styleable></resources>'),
      'R.txt': utf8.encode('int attr chipSize 0x0\nint attr icon 0x0\n'
          'int[] styleable Chip { 0x0, 0x0 }\n'
          'int styleable Chip_chipSize 0\nint styleable Chip_icon 1\n'),
      'classes.jar': _jar({}),
    });
    project.addDependencies(['chips.aar']);

    final build = await project.build();
    expect(build.exitCode, 0, reason: build.output);
    final prefix = '${project.package.replaceAll('.', '_')}_repacked_';
    final rTxt = utf8.decode(project.aix
        .library('${project.package}.repacked.chips.aar')
        .findFile('R.txt')!
        .content);
    expect(
        rTxt,
        allOf(
            contains('int attr icon '),
            contains('int attr ${prefix}chipSize '),
            isNot(contains('${prefix}icon'))));
  });

  test('private AARs whose code is unused ship without classes', () async {
    final project = await TestProject.create('private_res_ext');
    final classes = await _compiled(project, {
      'com/example/icons/Icons':
          'package com.example.icons; public class Icons {}',
    });
    _writeAar(project, 'icons.aar', {
      'AndroidManifest.xml':
          utf8.encode('<manifest package="com.example.icons"/>'),
      'res/drawable/play.xml': utf8.encode('<vector/>'),
      'R.txt': utf8.encode('int drawable play 0x0\n'),
      'classes.jar': _jar(classes),
    });
    project.addDependencies(['icons.aar']);
    project.placeLibraries({'icons.aar': 'private'});

    final build = await project.build();
    expect(build.exitCode, 0, reason: build.output);
    final aar = project.aix.library('${project.package}.repacked.icons.aar');
    expect(aar.findFile('classes.jar'), isNull);
    expect(
        aar.findFile('res/drawable/${project.package.replaceAll('.', '_')}'
            '_repacked_play.xml'),
        isNotNull);
  });

  test('optimized builds optimize private AARs into the extension', () async {
    final project = await TestProject.create('private_optimized_ext');
    final classes = await _compiled(project, {
      'com/example/player/PlaybackService': 'package com.example.player; '
          'public class PlaybackService { '
          'static int volume = Integer.getInteger("volume", 7); }',
      'com/example/player/Mixer': 'package com.example.player; '
          'class Mixer { public String toString() { '
          'return "volume " + PlaybackService.volume; } }',
      'com/example/player/Api': 'package com.example.player; '
          'public class Api { public static Object mixer() { '
          'return new Mixer(); } }',
      'com/example/player/Unused':
          'package com.example.player; public class Unused {}',
    });
    _writeAar(project, 'player.aar', {
      'AndroidManifest.xml': utf8
          .encode('<manifest xmlns:android="http://schemas.android.com/apk/res/'
              'android" package="com.example.player"><application>'
              '<service android:name=".PlaybackService"/>'
              '</application></manifest>'),
      'res/drawable/play.xml': utf8.encode('<vector/>'),
      'R.txt': utf8.encode('int drawable play 0x0\n'),
      'classes.jar': _jar(classes),
    });
    project.addDependencies(['player.aar']);
    project.placeLibraries({'player.aar': 'private'});
    project.writeJavaExtension('''
  @SimpleFunction
  public String Mixer() {
    return com.example.player.Api.mixer().toString();
  }
''');

    final build = await project.build(['--optimize']);
    expect(build.exitCode, 0, reason: build.output);
    final aix = project.aix;
    final shipped = [
      ...aix.classNames.where((el) => el.endsWith('.class')),
      ..._classesOf(aix.library('${project.package}.repacked.player.aar')),
    ];
    expect(shipped, everyElement(startsWith('${project.packagePath}/')));
    expect(
        shipped,
        contains(
            '${project.packagePath}/repacked/com/example/player/PlaybackService.class'));
    expect(
        project.file('out/${project.package}.mapping.txt').readAsStringSync(),
        allOf(contains('com.example.player.Mixer ->'),
            isNot(contains('com.example.player.Unused'))));
  });

  test('AAR manifests keep the app package for \${applicationId}', () async {
    final project = await TestProject.create('app_id_ext');
    project.file('deps/files.aar')
      ..createSync(recursive: true)
      ..writeAsBytesSync(ZipEncoder().encode(Archive()
        ..addFile(ArchiveFile.string(
            'AndroidManifest.xml',
            '<manifest xmlns:android="http://schemas.android.com/apk/res/'
                'android" package="com.example.files"><application>'
                '<provider android:name="com.example.files.LibraryProvider" '
                'android:authorities="\${applicationId}.library.files" '
                'android:exported="false"/></application></manifest>'))
        ..addFile(
            ArchiveFile.bytes('classes.jar', ZipEncoder().encode(Archive())))));
    project.addDependencies(['files.aar']);
    final manifest = project.file('src/AndroidManifest.xml');
    manifest.writeAsStringSync(manifest.readAsStringSync().replaceFirst(
        '<application>',
        '<application><provider android:name="com.example.ExtensionProvider" '
            'android:authorities="\${applicationId}.extension.files" '
            'android:exported="false"/>'));

    final build = await project.build();
    expect(build.exitCode, 0, reason: build.output);
    final buildInfo = jsonEncode(project.aix.buildInfo);
    expect(
        buildInfo,
        allOf(
            contains('%packageName%.library.files'),
            contains('%packageName%.extension.files'),
            isNot(contains('${project.package}.library.files')),
            isNot(contains('${project.package}.extension.files'))));
  });

  test('shipped AARs declare ids in the long form legacy aapt accepts',
      () async {
    final project = await TestProject.create('id_resources_ext');
    project.file('deps/owners.aar')
      ..createSync(recursive: true)
      ..writeAsBytesSync(ZipEncoder().encode(Archive()
        ..addFile(ArchiveFile.string(
            'AndroidManifest.xml',
            '<manifest xmlns:android="http://schemas.android.com/apk/res/'
                'android" package="com.example.owners"/>'))
        ..addFile(ArchiveFile.string('res/values/values.xml',
            '<resources><id name="view_tree_owner"/></resources>'))
        ..addFile(ArchiveFile.string('R.txt', 'int id view_tree_owner 0x0\n'))
        ..addFile(
            ArchiveFile.bytes('classes.jar', ZipEncoder().encode(Archive())))));
    project.addDependencies(['owners.aar']);

    final build = await project.build();
    expect(build.exitCode, 0, reason: build.output);
    final prefix = '${project.package.replaceAll('.', '_')}_repacked_';
    expect(
        utf8.decode(project.aix
            .library('${project.package}.repacked.owners.aar')
            .findFile('res/values/values.xml')!
            .content),
        '<resources><item name="${prefix}view_tree_owner" type="id"/>'
        '</resources>');
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
          contains('com.google.guava:guava:33.3.1-android (private: default)'));
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

    test('are refused as private when their assets or native code would break',
        () async {
      final project = await TestProject.create('private_native_ext');
      project.file('deps/native.aar')
        ..createSync(recursive: true)
        ..writeAsBytesSync(ZipEncoder().encode(Archive()
          ..addFile(ArchiveFile.string('AndroidManifest.xml',
              '<manifest package="com.example.native"/>'))
          ..addFile(ArchiveFile.string('assets/model.bin', 'model'))
          ..addFile(ArchiveFile.string('jni/arm64-v8a/libnative.so', 'elf'))
          ..addFile(ArchiveFile.bytes(
              'classes.jar', ZipEncoder().encode(Archive())))));
      project.addDependencies(['native.aar']);
      project.placeLibraries({'native.aar': 'private'});
      final build = await project.build();
      expect(build.exitCode, 1, reason: build.output);
      expect(
          build.output,
          contains("native.aar can't be private: its assets keep their "
              'original paths and its native libraries find classes by their '
              'original names'));
    });

    test('are refused as private when they bundle JARs', () async {
      final project = await TestProject.create('private_bundled_ext');
      project.file('deps/vendor.aar')
        ..createSync(recursive: true)
        ..writeAsBytesSync(_jar({
          'AndroidManifest.xml':
              utf8.encode('<manifest package="com.example.vendor"/>'),
          'libs/sdk.jar': _jar({'sdk.txt': utf8.encode('sdk')}),
          'classes.jar': _jar({}),
        }));
      project.addDependencies(['vendor.aar']);
      final build = await project.build();
      expect(build.exitCode, 1, reason: build.output);
      expect(
          build.output,
          contains("vendor.aar can't be private: the JARs in its libs/ "
              'folder keep their original names. Place it as shared in '
              'rush.yml: `libraries: {vendor.aar: shared}`.'));
    });

    test('are refused as private when a shared library uses them', () async {
      final project = await TestProject.create('private_used_ext');
      project.addDependencies(['androidx.media3:media3-common:1.11.1']);
      project.setMinSdk(23);
      project.placeLibraries({
        'androidx.media3:media3-common': 'shared',
        'com.google.guava:guava': 'private',
      });
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

    String renamed() => '${project.package}.repacked';

    String prefix() => '${project.package.replaceAll('.', '_')}_repacked_';

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
      final ui =
          aix.library('${renamed()}.androidx.media3-media3-ui-1.11.1.aar');
      expect(ui.findFile('res/raw/${prefix()}roboto_medium_numbers.ttf'),
          isNotNull);
      expect(ui.files.where((el) => el.name.startsWith('res/font')), isEmpty);
      expect(text(ui, 'R.txt'),
          contains('int raw ${prefix()}roboto_medium_numbers '));
      expect(text(ui, 'R.txt'), isNot(contains('int font ')));
    });

    test('are referenced as raw resources by dependent AARs', () {
      final player = aix.library('${renamed()}.player.aar');
      expect(text(player, 'res/values/styles.xml'),
          contains('@raw/${prefix()}roboto_medium_numbers'));
      expect(text(player, 'R.txt'),
          'int raw ${prefix()}roboto_medium_numbers 0x7f010001\n');
    });

    test('stay reachable through R.font', () {
      final repacked = '${project.packagePath}/repacked';
      expect(
          classNames(
              aix.library('${renamed()}.androidx.media3-media3-ui-1.11.1.aar')),
          contains('$repacked/androidx/media3/ui/R\$font.class'));
      expect(classNames(aix.library('${renamed()}.player.aar')),
          contains('$repacked/com/example/player/R\$font.class'));
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
