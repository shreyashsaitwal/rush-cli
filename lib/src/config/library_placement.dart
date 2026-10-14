enum LibraryPlacement { exclude, provided, shared, private }

String libraryKey(String dependency) {
  final parts = dependency.split(':');
  return parts.length >= 3 ? '${parts[0]}:${parts[1]}' : dependency;
}
