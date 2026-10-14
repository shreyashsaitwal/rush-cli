String withoutCommentsAbove(String text, bool Function(String line) isTarget) {
  final lines = text.split('\n');
  final comments = <int>{};
  for (final (index, line) in lines.indexed) {
    if (isTarget(line)) {
      for (var above = index - 1;
          above >= 0 && lines[above].startsWith('#');
          above--) {
        comments.add(above);
      }
    }
  }
  return [
    for (final (index, line) in lines.indexed)
      if (!comments.contains(index)) line,
  ].join('\n');
}
