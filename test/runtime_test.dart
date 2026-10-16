@Timeout(Duration(minutes: 3))
library;

import 'dart:io';

import 'package:test/test.dart';

import 'support/fixtures.dart';
import 'support/project.dart';

const _usesJavaTime = '''
  @SimpleFunction
  public String Tomorrow() {
    return java.time.LocalDate.of(2026, 10, 12).plusDays(1).toString();
  }
''';

void main() {
  group('core library', () {
    test('is backported from API 24 and only when used', () async {
      final project = await TestProject.create('time_ext');
      project.setMinSdk(24);
      final unused = await project.build();
      expect(unused.exitCode, 0, reason: unused.output);
      expect(project.aix.classNames.where((c) => c.contains(r'j$/')), isEmpty);

      project.writeJavaExtension(_usesJavaTime);
      final used = await project.build();
      expect(used.exitCode, 0, reason: used.output);
      final classNames = project.aix.classNames;
      final backport = classNames
          .where((c) => c.startsWith('${project.packagePath}/repacked/j\$/'));
      expect(backport,
          contains('${project.packagePath}/repacked/j\$/time/LocalDate.class'));
      expect(backport.length, lessThan(200));
      expect(
          classNames
              .where((c) => c.startsWith(r'j$/') || c.startsWith('java/')),
          isEmpty);
    });

    test('is backported in optimized Kotlin builds', () async {
      final project =
          await TestProject.create('kotlin_time_ext', language: 'kotlin');
      project.setMinSdk(24);
      project.writeSource('${project.className}.kt', '''
package {package}

import com.google.appinventor.components.annotations.Extension
import com.google.appinventor.components.annotations.SimpleFunction
import com.google.appinventor.components.runtime.AndroidNonvisibleComponent
import com.google.appinventor.components.runtime.ComponentContainer
import java.time.LocalDate

@Extension(description = "Test extension", icon = "icon.png")
class {className}(container: ComponentContainer) : AndroidNonvisibleComponent(container.`\$form`()) {
    @SimpleFunction
    fun Tomorrow(): String = "\${LocalDate.of(2026, 10, 12).plusDays(1)} \${listOf(3, 1, 2).sorted()}"
}
''');
      final result = await project.build(['--optimize']);
      expect(result.exitCode, 0, reason: result.output);
      expect(project.aix.classNames,
          contains('${project.packagePath}/repacked/j\$/time/LocalDate.class'));
    });

    test('is not backported below API 24', () async {
      final project = await TestProject.create('old_time_ext');
      project.writeJavaExtension(_usesJavaTime);
      final result = await project.build();
      expect(result.exitCode, 0, reason: result.output);
      expect(project.aix.classNames.where((c) => c.contains(r'j$/')), isEmpty);
    });
  });

  group('optimize', () {
    test('works with a library App Inventor also ships', () async {
      final project = await TestProject.create('gson_ext');
      project.addDependencies(['com.google.code.gson:gson:2.8.9']);
      final result = await project.build(['--optimize']);
      expect(result.exitCode, 0, reason: result.output);
    });

    test('keeps the creators Android finds parcelables by', () async {
      final project = await TestProject.create('parcel_ext');
      project.writeSource('helpers/Point.java', '''
package {package}.helpers;

import android.os.Parcel;
import android.os.Parcelable;

public class Point implements Parcelable {
  public final int x;

  public Point(int x) {
    this.x = x;
  }

  public int describeContents() {
    return 0;
  }

  public void writeToParcel(Parcel out, int flags) {
    out.writeInt(x);
  }

  public static final Creator<Point> CREATOR = new Creator<Point>() {
    public Point createFromParcel(Parcel in) {
      return new Point(in.readInt());
    }

    public Point[] newArray(int size) {
      return new Point[size];
    }
  };
}
''');
      project.writeJavaExtension('''
  @SimpleFunction
  public int RoundTrip(int x) {
    android.os.Bundle bundle = new android.os.Bundle();
    bundle.putParcelable("point", new {package}.helpers.Point(x));
    android.os.Parcel parcel = android.os.Parcel.obtain();
    parcel.writeBundle(bundle);
    parcel.setDataPosition(0);
    android.os.Bundle read = parcel.readBundle(getClass().getClassLoader());
    return (({package}.helpers.Point) read.getParcelable("point")).x;
  }
''');

      final result = await project.build(['--optimize']);
      expect(result.exitCode, 0, reason: result.output);
      final point = RegExp(
              '^${RegExp.escape(project.package)}'
              r'\.helpers\.Point -> (\S+):$',
              multiLine: true)
          .firstMatch(project
              .file('out/${project.package}.mapping.txt')
              .readAsStringSync())![1]!;
      expect(project.aix.fieldNames(point.replaceAll('.', '/')),
          contains('CREATOR'));
    });

    test('works with annotations that reference the Java compiler API',
        () async {
      final project = await TestProject.create('annotations_ext');
      project.addDependencies(
          ['com.google.errorprone:error_prone_annotations:2.27.0']);
      final result = await project.build(['--optimize']);
      expect(result.exitCode, 0, reason: result.output);
    });

    group('of a Kotlin extension with AARs that depend on bundled libraries',
        () {
      late TestProject project;
      late ProcessResult build;

      setUpAll(() async {
        project = await TestProject.create('ktx_ext', language: 'kotlin');
        project.addDependencies(['androidx.core:core-ktx:1.5.0']);
        build = await project.build(['--optimize']);
        if (build.exitCode != 0) fail(build.output);
      });

      test('ships the bundled libraries as AARs', () {
        expect(project.aix.libraries,
            anyElement(startsWith('org.jetbrains.kotlin-kotlin-stdlib-')));
      });

      test('keeps ProGuard notes out of the output', () {
        expect(build.output, isNot(contains('ProGuard, version')));
        expect(build.output, isNot(contains('proguard/manual')));
      });
    });
  });
}
