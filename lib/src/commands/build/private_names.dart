import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:collection/collection.dart';
import 'package:xml/xml.dart';

import 'package:rush/src/commands/build/aar_contents.dart';
import 'package:rush/src/commands/build/android_xml.dart';
import 'package:rush/src/commands/build/relocation.dart' as relocation;
import 'package:rush/src/commands/build/resource_names.dart';

typedef ExtensionSymbols = ({Archive resources, String symbols});

const _componentElements = {
  'application',
  'activity',
  'activity-alias',
  'service',
  'receiver',
  'provider',
  'instrumentation',
};

const _classNameAttributes = {
  'android:name',
  'android:targetActivity',
  'android:parentActivityName',
  'android:backupAgent',
  'android:manageSpaceActivity',
  'android:appComponentFactory',
};

class PrivateNames {
  factory PrivateNames({
    required String package,
    required Set<String> classes,
    required Map<String, Archive> aars,
    Set<String> originalPackages = const {},
    Iterable<String> manifestElements = const [],
    ExtensionSymbols? extensionResources,
    ResourceDefinitions? appInventor,
  }) {
    final resources = ResourceRenaming.of(aars.values,
        prefix: resourcePrefix(package), appInventor: appInventor);
    final rClasses = <String>{};
    final rFields = <relocation.RenamedMember>[];
    for (final MapEntry(key: fileName, value: aar) in aars.entries) {
      final owner = _rClass(_packageOf(aar, fileName));
      final rTxt = aar.text('R.txt') ?? '';
      final types = rTxtRows(rTxt).map((el) => el.type).toSet();
      if (types.isNotEmpty) {
        rClasses.addAll([owner, for (final type in types) '$owner\$$type']);
      }
      rFields.addAll([
        for (final field in resources.renamedFields(rTxt))
          (owner: '$owner\$${field.type}', name: field.from, to: field.to),
      ]);
    }
    final extension = switch (extensionResources) {
      final extension? => resources.renameExtensionSymbols(
          extension.symbols, ResourceDefinitions.of([extension.resources])),
      null => null,
    };
    rFields.addAll([
      for (final field in extension?.fields ?? const <RenamedField>[])
        (
          owner: '${_rClass(package)}\$${field.type}',
          name: field.from,
          to: field.to,
        ),
    ]);
    final prefix = _classPrefix(package);
    final renamed = {
      ...classes.whereNot((el) =>
          el.startsWith(prefix) ||
          originalPackages.contains(relocation.classPackage(el))),
      ...rClasses,
    };
    final intentNames = {
      for (final aar in aars.values)
        if (aar.text('AndroidManifest.xml') case final manifest?)
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
        resources,
        extension?.symbols);
  }

  PrivateNames._(this.package, this._classes, this._rFields, this._keptStrings,
      this.resources, this.extensionSymbols);

  final String package;
  final Set<String> _classes;
  final List<relocation.RenamedMember> _rFields;
  final Set<String> _keptStrings;
  final ResourceRenaming resources;
  final String? extensionSymbols;

  static String resourcePrefix(String package) =>
      '${ownResourcePrefix(package)}repacked_';

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
        final name when isResourceXml(name) =>
          utf8.encode(_resourceWithRenamedClasses(utf8.decode(file.content))),
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
    final original = root.getAttribute('package');
    if (original != null) _expandRelativeNames(document, original);
    root.setAttribute('package', '$package.repacked.$original');
    _renameClassNames(document);
    return document.toXmlString();
  }

  static void _expandRelativeNames(XmlNode root, String package) {
    for (final attribute in root.descendantElements
        .where((el) => _componentElements.contains(el.name.qualified))
        .expand((el) => el.attributes)
        .where((el) => _classNameAttributes.contains(el.name.qualified))) {
      if (attribute.value.startsWith('.')) {
        attribute.value = '$package${attribute.value}';
      }
    }
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
        .expand((el) => el.attributes)) {
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

  String renameExtensionResource(String xml) {
    final document = parseAndroidXml(xml);
    final original = document.toXmlString();
    _renameClassReferences(document);
    resources.renameLibraryReferences(document);
    final renamed = document.toXmlString();
    return renamed == original ? xml : renamed;
  }

  String _resourceWithRenamedClasses(String xml) {
    final document = parseAndroidXml(xml);
    _renameClassReferences(document);
    return document.toXmlString();
  }

  void _renameClassReferences(XmlDocument document) {
    for (final text in document.descendants.whereType<XmlText>()) {
      final name = text.value.trim();
      text.value = text.value.replaceFirst(name, className(name));
    }
    for (final element in document.descendantElements.toList().reversed) {
      for (final attribute in element.attributes) {
        attribute.value = className(attribute.value);
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
  }

  static String _packageOf(Archive aar, String fileName) =>
      aar.package ??
      (throw Exception('$fileName declares no package in its manifest'));

  static String _rClass(String package) => '${package.replaceAll('.', '/')}/R';
}
