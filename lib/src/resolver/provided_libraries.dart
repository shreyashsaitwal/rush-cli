import 'package:collection/collection.dart';

import 'package:rush/src/config/library_placement.dart';

Set<String> providedOnly({
  required Iterable<String> roots,
  required Map<String, List<String>> dependencies,
  required Set<String> provided,
}) {
  bool isProvided(String coordinate) =>
      provided.contains(libraryKey(coordinate));
  final shipped = _reachable(roots.whereNot(isProvided), dependencies,
      through: (coordinate) => !isProvided(coordinate));
  return _reachable(roots, dependencies, through: (_) => true)
      .difference(shipped);
}

Set<String> _reachable(
  Iterable<String> roots,
  Map<String, List<String>> dependencies, {
  required bool Function(String coordinate) through,
}) {
  final reached = <String>{};
  final pending = [...roots];
  while (pending.isNotEmpty) {
    final coordinate = pending.removeLast();
    if (reached.add(coordinate)) {
      pending.addAll((dependencies[coordinate] ?? const []).where(through));
    }
  }
  return reached;
}
