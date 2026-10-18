import 'dart:convert';

import 'package:rush/src/commands/build/native_names.dart';
import 'package:test/test.dart';

const _classes = {
  'com/example/Codec',
  'com/example/Native_Lib',
  'com/example/Callback',
  'com/example/Callback\$Result',
  'com/example/Loader',
  'com/example/Event',
  'com/example/Unused',
  'a',
};

const _elfHeader = [0x7f, 0x45, 0x4c, 0x46, 0x02, 0x01];

List<int> _library(List<String> strings) => [
      ..._elfHeader,
      for (final string in strings) ...[...utf8.encode(string), 0, 0x90],
    ];

void main() {
  test('finds classes bound by exported JNI symbols', () {
    expect(
        namedClasses(
            _library([
              'Java_com_example_Codec_decode',
              'Java_com_example_Codec_decode__I',
              'Java_com_example_Native_1Lib_create',
            ]),
            _classes),
        {'com/example/Codec', 'com/example/Native_Lib'});
  });

  test('decodes escapes followed by hex digits and nested classes', () {
    expect(
        namedClasses(
            _library([
              'Java_com_example_my_1face_Native_run',
              'Java_com_example_Api_11234_call',
              'Java_com_example_Outer_00024Inner_run',
            ]),
            {
              'com/example/my_face/Native',
              'com/example/Api_1234',
              'com/example/Outer\$Inner',
            }),
        {
          'com/example/my_face/Native',
          'com/example/Api_1234',
          'com/example/Outer\$Inner',
        });
  });

  test('ignores malformed JNI symbols', () {
    expect(
        namedClasses(_library(['Java_a_0_b', 'Java_lib_0zz_x']), {'lib/Codec'}),
        isEmpty);
  });

  test('finds classes looked up by name and in method descriptors', () {
    expect(
        namedClasses(
            _library([
              'com/example/Event',
              '(ILcom/example/Callback;)Lcom/example/Callback\$Result;',
            ]),
            _classes),
        {
          'com/example/Event',
          'com/example/Callback',
          'com/example/Callback\$Result'
        });
  });

  test('finds classes loaded by their dotted names', () {
    expect(namedClasses(_library(['>com.example.Loader']), _classes),
        {'com/example/Loader'});
  });

  test('ignores names of classes the program does not have', () {
    expect(
        namedClasses(
            _library([
              'java/lang/String',
              'Java_org_other_Thing_run',
              'org.other.Thing',
              'a',
              'Codec',
            ]),
            _classes),
        isEmpty);
  });
}
