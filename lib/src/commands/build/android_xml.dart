import 'package:xml/xml.dart';
import 'package:xml/xml_events.dart';

XmlDocument parseAndroidXml(String xml) =>
    XmlDocument.parse(_withNormalizedAttributeValues(xml));

XmlDocumentFragment parseAndroidXmlFragment(String xml) =>
    XmlDocumentFragment.parse(_withNormalizedAttributeValues(xml));

String _withNormalizedAttributeValues(String xml) {
  final normalized = StringBuffer();
  var copied = 0;
  for (final tag in parseEvents(xml, withLocation: true)
      .whereType<XmlStartElementEvent>()) {
    normalized
      ..write(xml.substring(copied, tag.start))
      ..write(_normalizedTag(xml.substring(tag.start!, tag.stop)));
    copied = tag.stop!;
  }
  return (normalized..write(xml.substring(copied))).toString();
}

String _normalizedTag(String tag) {
  final normalized = StringBuffer();
  String? quote;
  for (final character in tag.replaceAll('\r\n', '\n').split('')) {
    if (quote == null) {
      quote = character == '"' || character == "'" ? character : null;
    } else if (character == quote) {
      quote = null;
    }
    final inValue = quote != null && character != quote;
    normalized.write(inValue && '\n\r\t'.contains(character) ? ' ' : character);
  }
  return normalized.toString();
}
