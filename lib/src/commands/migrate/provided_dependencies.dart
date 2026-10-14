import 'package:collection/collection.dart';
import 'package:yaml_edit/yaml_edit.dart';

import 'package:rush/src/config/library_placement.dart';

const _key = 'provided_dependencies';

String withProvidedDependenciesAsLibraries(String config) {
  final editor = YamlEditor(_withoutCommentAbove(config, _key));
  final document = editor.parseAt([]).value as Map;
  final provided = [...?document[_key] as List?].cast<String>();
  final dependencies = [...?document['dependencies'] as List?];
  final libraries = document['libraries'] as Map? ?? const {};

  final added = provided.whereNot(dependencies.contains).toList();
  if (document['dependencies'] == null) {
    editor.update(['dependencies'], added);
  } else {
    for (final dependency in added) {
      editor.appendToList(['dependencies'], dependency);
    }
  }

  final placements = {
    for (final dependency in provided)
      if (!libraries.containsKey(libraryKey(dependency)))
        libraryKey(dependency): LibraryPlacement.provided.name,
  };
  if (document['libraries'] == null) {
    editor.update(['libraries'], placements);
  } else {
    for (final MapEntry(key: library, value: placement) in placements.entries) {
      editor.update(['libraries', library], placement);
    }
  }

  editor.remove([_key]);
  return editor.toString();
}

String _withoutCommentAbove(String config, String key) {
  final lines = config.split('\n');
  final keyLine = lines.indexWhere((el) => el.startsWith('$key:'));
  var commentStart = keyLine;
  while (commentStart > 0 && lines[commentStart - 1].startsWith('#')) {
    commentStart--;
  }
  return [...lines.take(commentStart), ...lines.skip(keyLine)].join('\n');
}
