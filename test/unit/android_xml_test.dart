import 'package:rush/src/commands/build/android_xml.dart';
import 'package:test/test.dart';

void main() {
  test('turns line breaks typed in attribute values into spaces', () {
    expect(
        parseAndroidXml('<path pathData="M10 9L5 4\n17 7\r\n20 9\tZ"/>')
            .toXmlString(),
        '<path pathData="M10 9L5 4 17 7 20 9 Z"/>');
  });

  test('keeps escaped line breaks in attribute values', () {
    expect(parseAndroidXml('<TextView text="one&#10;two"/>').toXmlString(),
        '<TextView text="one&#xA;two"/>');
  });

  test('keeps line breaks between attributes and in text', () {
    expect(
        parseAndroidXml('<resources>\n<string\n    name="a">one\ntwo</string>'
                '</resources>')
            .toXmlString(),
        '<resources>\n<string name="a">one\ntwo</string></resources>');
  });

  test('parses manifest fragments the same way', () {
    expect(
        parseAndroidXmlFragment('<service android:icon="@drawable/a\nb"/>')
            .children
            .single
            .toXmlString(),
        '<service android:icon="@drawable/a b"/>');
  });
}
