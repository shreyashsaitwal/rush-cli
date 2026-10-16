import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:collection/collection.dart';
import 'package:xml/xml.dart';

import 'package:rush/src/commands/build/android_manifest.dart';
import 'package:rush/src/commands/build/android_xml.dart';
import 'package:rush/src/commands/build/relocation.dart' as relocation;
import 'package:rush/src/commands/build/resource_names.dart';

class PrivateNames {
  factory PrivateNames({
    required String package,
    required Set<String> classes,
    required Map<String, Archive> aars,
    Iterable<String> manifestElements = const [],
  }) {
    final resources = ResourceRenaming.of(aars.values,
        prefix: '${package.replaceAll('.', '_')}_');
    final rClasses = <String>{};
    final rFields = <relocation.RenamedMember>[];
    for (final MapEntry(key: fileName, value: aar) in aars.entries) {
      final owner = _rClass(_packageOf(aar, fileName));
      final rTxt = _text(aar, 'R.txt') ?? '';
      final types = const LineSplitter()
          .convert(rTxt)
          .map((line) => line.split(' '))
          .where((parts) => parts.length >= 3)
          .map((parts) => parts[1])
          .toSet();
      if (types.isNotEmpty) {
        rClasses.addAll([owner, for (final type in types) '$owner\$$type']);
      }
      rFields.addAll([
        for (final field in resources.renamedFields(rTxt))
          (owner: '$owner\$${field.type}', name: field.from, to: field.to),
      ]);
    }
    final prefix = _classPrefix(package);
    final renamed = {
      ...classes.whereNot((el) => el.startsWith(prefix)),
      ...rClasses,
    };
    final intentNames = {
      for (final aar in aars.values)
        if (_text(aar, 'AndroidManifest.xml') case final manifest?)
          ..._intentNames(parseAndroidXml(manifest)),
      for (final element in manifestElements)
        ..._intentNames(parseAndroidXmlFragment(element)),
    };
    return PrivateNames._(
        package,
        renamed,
        rFields,
        intentNames
            .where((el) => renamed.contains(el.replaceAll('.', '/')))
            .toSet(),
        resources);
  }

  PrivateNames._(this.package, this._classes, this._rFields, this._keptStrings,
      this.resources);

  final String package;
  final Set<String> _classes;
  final List<relocation.RenamedMember> _rFields;
  final Set<String> _keptStrings;
  final ResourceRenaming resources;

  static String _classPrefix(String package) =>
      '${package.replaceAll('.', '/')}/repacked/';

  String get relocationSpec => relocation.relocationSpec(
        _classPrefix(package),
        _classes.sorted(),
        fields: _rFields.sortedBy((el) => '${el.owner} ${el.name}'),
        keptStrings: _keptStrings.sorted(),
      );

  String className(String name) => _classes.contains(name.replaceAll('.', '/'))
      ? '$package.repacked.$name'
      : name;

  String aarFileName(String fileName) => '$package.repacked.$fileName';

  Archive renameAar(Archive aar, {required List<int>? classes}) {
    final renamed = Archive();
    for (final file in resources.rename(aar).files) {
      final content = switch (file.name) {
        'classes.jar' => classes,
        'AndroidManifest.xml' => utf8.encode(_renamedManifest(file)),
        final name when name.startsWith('res/') && name.endsWith('.xml') =>
          utf8.encode(_renamedViews(file)),
        _ => file.content,
      };
      if (content != null) {
        renamed.add(ArchiveFile.bytes(file.name, content));
      }
    }
    return renamed;
  }

  List<Map<String, dynamic>> renameBuildInfos(
          List<Map<String, dynamic>> buildInfos) =>
      [
        for (final info in buildInfos)
          {
            ...info,
            if (info['activities'] case final List<dynamic> elements)
              'activities': [
                for (final String element in elements)
                  _renamedFragment(element),
              ],
          },
      ];

  String _renamedManifest(ArchiveFile manifest) {
    final document = parseAndroidXml(utf8.decode(manifest.content));
    final root = document.rootElement;
    root.setAttribute(
        'package', '$package.repacked.${root.getAttribute('package')}');
    _renameClassNames(document);
    return document.toXmlString();
  }

  String _renamedFragment(String element) {
    final fragment = parseAndroidXmlFragment(element);
    final original = _serialized(fragment);
    _renameClassNames(fragment);
    resources.renameReferences(fragment);
    final renamed = _serialized(fragment);
    return renamed == original ? element : renamed;
  }

  static String _serialized(XmlDocumentFragment fragment) =>
      fragment.children.map((el) => el.toXmlString()).join();

  void _renameClassNames(XmlNode root) {
    for (final attribute in root.descendantElements
        .whereNot(_isIntentName)
        .expand((el) => el.attributes)
        .where((el) => el.name.qualified == 'android:name')) {
      attribute.value = _renamedName(attribute.value);
    }
  }

  static bool _isIntentName(XmlElement element) =>
      const {'action', 'category'}.contains(element.name.qualified);

  static Iterable<String> _intentNames(XmlNode root) => root.descendantElements
      .where(_isIntentName)
      .map((el) => el.getAttribute('android:name'))
      .nonNulls;

  String _renamedName(String name) => switch (name.lastIndexOf(':')) {
        -1 => className(name),
        final colon =>
          name.substring(0, colon + 1) + className(name.substring(colon + 1)),
      };

  String _renamedViews(ArchiveFile file) {
    final document = parseAndroidXml(utf8.decode(file.content));
    for (final element in document.descendantElements.toList().reversed) {
      final view = element.getAttribute('class');
      if (view != null) {
        element.setAttribute('class', className(view));
      }
      final renamed = className(element.name.qualified);
      if (renamed != element.name.qualified) {
        element.replace(XmlElement(
          XmlName(renamed),
          element.attributes.map((el) => el.copy()),
          element.children.map((el) => el.copy()),
          element.isSelfClosing,
        ));
      }
    }
    return document.toXmlString();
  }

  static String _packageOf(Archive aar, String fileName) =>
      manifestPackage(_text(aar, 'AndroidManifest.xml') ?? '') ??
      (throw Exception('$fileName declares no package in its manifest'));

  static String _rClass(String package) => '${package.replaceAll('.', '/')}/R';

  static String? _text(Archive aar, String name) =>
      switch (aar.findFile(name)) {
        final file? => utf8.decode(file.content),
        null => null,
      };
}
