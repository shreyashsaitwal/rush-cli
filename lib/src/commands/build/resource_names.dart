import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:collection/collection.dart';
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

import 'package:rush/src/commands/build/aar_contents.dart';
import 'package:rush/src/commands/build/android_xml.dart';

typedef RenamedField = ({String type, String from, String to});

const _fileTypes = {
  'anim',
  'animator',
  'color',
  'drawable',
  'font',
  'interpolator',
  'layout',
  'menu',
  'mipmap',
  'navigation',
  'raw',
  'transition',
  'xml',
};
const _valueTypes = {
  'array': 'array',
  'bool': 'bool',
  'color': 'color',
  'dimen': 'dimen',
  'drawable': 'drawable',
  'fraction': 'fraction',
  'id': 'id',
  'integer': 'integer',
  'integer-array': 'array',
  'plurals': 'plurals',
  'string': 'string',
  'string-array': 'array',
  'style': 'style',
};
const _resAuto = 'http://schemas.android.com/apk/res-auto';
final _reference = RegExp(r'^@(\+?)([a-z]+)/([\w.]+)$');
final _themeReference = RegExp(r'^\?(attr/)?([A-Za-z_]\w*)$');

String ownResourcePrefix(String package) =>
    '${package.toLowerCase().replaceAll('.', '_')}_';

String resourceField(String name) =>
    name.replaceAll('.', '_').replaceAll(':', '_');

class ResourceDefinitions {
  ResourceDefinitions._(this.defined, this.styleables, this._attributes);

  factory ResourceDefinitions.of(Iterable<Archive> libraries) {
    final defined = <(String, String)>{};
    final styleables = <String, List<String>>{};
    final attributes = <String, XmlElement>{};
    for (final file in libraries.expand((el) => el.files)) {
      final resource = _ResourceFile.parse(file.name);
      if (resource != null) {
        defined.add((resource.type, resource.name));
      }
      if (isResourceXml(file.name)) {
        final document = resourceDocument(file);
        if (_isValues(file.name)) {
          _collectValues(document.rootElement, defined, styleables, attributes);
        } else {
          _collectIds(document, defined);
        }
      }
    }
    return ResourceDefinitions._(defined, styleables, attributes);
  }

  final Set<(String, String)> defined;
  final Map<String, List<String>> styleables;
  final Map<String, XmlElement> _attributes;

  String get stubs => [
        '<resources>',
        for (final name in _attributes.keys.sorted())
          _attributes[name]!.toXmlString(),
        for (final (type, name) in defined
            .where((el) => el.$1 != 'attr' && el.$1 != 'styleable')
            .sorted((a, b) => '${a.$1} ${a.$2}'.compareTo('${b.$1} ${b.$2}')))
          switch (type) {
            'style' => '<style name="$name" parent=""/>',
            'id' => '<item type="id" name="$name"/>',
            _ => '<item type="$type" name="$name">@null</item>',
          },
        '</resources>',
      ].join();

  static void _collectValues(
      XmlElement resources,
      Set<(String, String)> defined,
      Map<String, List<String>> styleables,
      Map<String, XmlElement> attributes) {
    for (final element in resources.childElements) {
      final type = _definedType(element);
      final elementName = element.getAttribute('name');
      if (type == null || elementName == null) {
        continue;
      }
      defined.add((type, elementName));
      if (type == 'attr') {
        attributes[elementName] = element.copy();
      }
      if (element.localName == 'declare-styleable') {
        final attrs = element.findElements('attr').toList();
        styleables[elementName] = [
          for (final attr in attrs) attr.getAttribute('name')!,
        ];
        for (final attr in attrs.where(_definesAttribute)) {
          defined.add(('attr', attr.getAttribute('name')!));
          attributes[attr.getAttribute('name')!] = attr.copy();
        }
      }
    }
  }

  static void _collectIds(XmlDocument document, Set<(String, String)> defined) {
    for (final attribute
        in document.descendantElements.expand((el) => el.attributes)) {
      final reference = _reference.firstMatch(attribute.value);
      if (reference != null && reference[1] == '+' && reference[2] == 'id') {
        defined.add(('id', reference[3]!));
      }
    }
  }

  static bool _definesAttribute(XmlElement attr) =>
      !attr.getAttribute('name')!.startsWith('android:') &&
      (attr.getAttribute('format') != null || attr.childElements.isNotEmpty);
}

class ResourceRenaming {
  ResourceRenaming._(
      this._prefix, this._defined, Map<String, List<String>> styleables)
      : _fields = _renamedFieldNames(_prefix, _defined, styleables);

  factory ResourceRenaming.of(Iterable<Archive> libraries,
      {required String prefix, Iterable<Archive> appInventor = const []}) {
    final definitions = ResourceDefinitions.of(libraries);
    return ResourceRenaming._(
        prefix,
        definitions.defined
            .difference(ResourceDefinitions.of(appInventor).defined),
        definitions.styleables);
  }

  final String _prefix;
  final Set<(String, String)> _defined;
  final Map<(String, String), String> _fields;

  String name(String type, String name) =>
      _defined.contains((type, name)) ? '$_prefix$name' : name;

  Archive rename(Archive library) {
    final renamed = Archive();
    for (final file in library.files.where((el) => el.isFile)) {
      final resource = _ResourceFile.parse(file.name);
      final path = resource == null
          ? file.name
          : resource.withName(name(resource.type, resource.name));
      renamed.add(ArchiveFile.bytes(path, _renamedContent(file)));
    }
    return renamed;
  }

  List<RenamedField> renamedFields(String rTxt) => _renamedRows(rTxt, _fields);

  List<RenamedField> renamedExtensionFields(
          String rTxt, ResourceDefinitions extension) =>
      _renamedRows(rTxt, _extensionFields(extension));

  String renameExtensionSymbols(String rTxt, ResourceDefinitions extension) =>
      _renamedSymbols(rTxt, _extensionFields(extension));

  Map<(String, String), String> _extensionFields(
          ResourceDefinitions extension) =>
      {
        ..._fields,
        for (final MapEntry(key: styleable, value: attrs)
            in extension.styleables.entries)
          for (final attr in attrs)
            if (_defined.contains(('attr', attr)))
              (
                'styleable',
                '${resourceField(styleable)}_${resourceField(attr)}'
              ): '${resourceField(styleable)}_'
                  '${resourceField(name('attr', attr))}',
      };

  static List<RenamedField> _renamedRows(
          String rTxt, Map<(String, String), String> fields) =>
      [
        for (final row in rTxtRows(rTxt))
          if (fields[(row.type, row.name)] case final to?)
            (type: row.type, from: row.name, to: to),
      ];

  List<int> _renamedContent(ArchiveFile file) {
    if (file.name == 'R.txt') {
      return utf8.encode(_renamedSymbols(utf8.decode(file.content), _fields));
    }
    final resourceXml = isResourceXml(file.name);
    if (!resourceXml && file.name != 'AndroidManifest.xml') {
      return file.content;
    }
    final document = resourceXml
        ? resourceDocument(file)
        : parseAndroidXml(utf8.decode(file.content));
    renameReferences(document);
    if (resourceXml && _isValues(file.name)) {
      _renameValues(document.rootElement);
    }
    return utf8.encode(document.toXmlString());
  }

  static String _renamedSymbols(
          String rTxt, Map<(String, String), String> fields) =>
      const LineSplitter()
          .convert(rTxt)
          .map((line) {
            final parts = line.split(' ');
            if (parts.length < 3) {
              return line;
            }
            final field = fields[(parts[1], parts[2])];
            return field == null ? line : (parts..[2] = field).join(' ');
          })
          .map((line) => '$line\n')
          .join();

  void renameReferences(XmlNode root) {
    for (final element in root.descendantElements) {
      for (final attribute in [...element.attributes]) {
        attribute.value = _renamedReference(attribute.value);
        if (attribute.name.namespaceUri == _resAuto) {
          final renamed = name('attr', attribute.name.local);
          if (renamed != attribute.name.local) {
            attribute.replace(XmlAttribute(
                XmlName(renamed, attribute.name.prefix),
                attribute.value,
                attribute.attributeType));
          }
        }
      }
      for (final text in element.children.whereType<XmlText>()) {
        final value = text.value.trim();
        final renamed = _renamedReference(value);
        if (renamed != value) {
          text.value = text.value.replaceFirst(value, renamed);
        }
      }
    }
  }

  String _renamedReference(String value) {
    final reference = _reference.firstMatch(value);
    if (reference != null) {
      final type = reference[2]!;
      return '@${reference[1]}$type/${name(type, reference[3]!)}';
    }
    final theme = _themeReference.firstMatch(value);
    if (theme != null) {
      return '?${theme[1] ?? ''}${name('attr', theme[2]!)}';
    }
    return value;
  }

  void _renameValues(XmlElement resources) {
    for (final element in resources.childElements) {
      final type = _definedType(element);
      if (type == null) {
        continue;
      }
      final original = element.getAttribute('name')!;
      element.setAttribute('name', name(type, original));
      switch (element.localName) {
        case 'style':
          _renameStyle(element, original);
        case 'declare-styleable':
          _renameStyleableAttributes(element);
      }
    }
  }

  void renameLibraryReferences(XmlNode root) {
    renameReferences(root);
    for (final element in root.descendantElements) {
      switch (element.localName) {
        case 'style':
          _renameStyleReferences(element);
        case 'declare-styleable':
          _renameStyleableAttributes(element);
      }
    }
  }

  void _renameStyleableAttributes(XmlElement styleable) {
    for (final attr in styleable.findElements('attr')) {
      attr.setAttribute('name', name('attr', attr.getAttribute('name')!));
    }
  }

  void _renameStyle(XmlElement style, String original) {
    if (style.getAttribute('parent') == null && original.contains('.')) {
      final implied = original.substring(0, original.lastIndexOf('.'));
      style.setAttribute('parent', '@style/${name('style', implied)}');
    }
    _renameStyleReferences(style);
  }

  void _renameStyleReferences(XmlElement style) {
    final parent = style.getAttribute('parent');
    if (parent != null && !parent.startsWith('@')) {
      style.setAttribute('parent', name('style', parent));
    }
    for (final item in style.findElements('item')) {
      item.setAttribute('name', name('attr', item.getAttribute('name')!));
    }
  }

  static Map<(String, String), String> _renamedFieldNames(String prefix,
      Set<(String, String)> defined, Map<String, List<String>> styleables) {
    String renamed(String type, String name) =>
        defined.contains((type, name)) ? '$prefix$name' : name;
    return {
      for (final (type, name) in defined)
        (type, resourceField(name)): resourceField('$prefix$name'),
      for (final MapEntry(key: styleable, value: attrs) in styleables.entries)
        for (final attr in attrs)
          if (defined.contains(('styleable', styleable)) ||
              defined.contains(('attr', attr)))
            ('styleable', '${styleable}_${resourceField(attr)}'):
                '${resourceField(renamed('styleable', styleable))}_'
                    '${resourceField(renamed('attr', attr))}',
    };
  }
}

String? _definedType(XmlElement element) => switch (element.localName) {
      'attr' => 'attr',
      'declare-styleable' => 'styleable',
      'item' => element.getAttribute('type'),
      final tag => _valueTypes[tag],
    };

bool _isValues(String path) => p.posix.split(path)[1].startsWith('values');

class _ResourceFile {
  const _ResourceFile(this.directory, this.type, this.name, this.extension);

  static _ResourceFile? parse(String path) {
    final parts = p.posix.split(path);
    if (parts.length != 3 || parts[0] != 'res') {
      return null;
    }
    final type = parts[1].split('-').first;
    if (!_fileTypes.contains(type)) {
      return null;
    }
    final dot = parts[2].indexOf('.');
    return dot < 0
        ? null
        : _ResourceFile(parts[1], type, parts[2].substring(0, dot),
            parts[2].substring(dot));
  }

  final String directory;
  final String type;
  final String name;
  final String extension;

  String withName(String renamed) => 'res/$directory/$renamed$extension';
}
