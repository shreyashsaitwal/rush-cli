import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

final _classMapping = RegExp(r'^(\S+) -> (\S+):$', multiLine: true);

class ProgramSplit {
  factory ProgramSplit(
    Archive output, {
    required String mapping,
    required Map<String, String> aarOf,
    required Set<String> privateClasses,
  }) {
    final originalOf = {
      for (final match in _classMapping.allMatches(mapping))
        _internal(match[2]!): _internal(match[1]!),
    };
    final runtime = <ArchiveFile>[];
    final aars = <String, List<ArchiveFile>>{};
    final private = <String>{};
    for (final file in output.files.where(_isClass)) {
      final name = p.posix.withoutExtension(file.name);
      final original = originalOf[name] ?? name;
      if (privateClasses.contains(original)) {
        private.add(name);
      }
      switch (aarOf[original]) {
        case final aar?:
          aars.putIfAbsent(aar, () => []).add(file);
        case null:
          runtime.add(file);
      }
    }
    return ProgramSplit._(runtime, aars, private);
  }

  ProgramSplit._(this.runtime, this.aars, this.privateClasses);

  final List<ArchiveFile> runtime;
  final Map<String, List<ArchiveFile>> aars;
  final Set<String> privateClasses;

  static String _internal(String name) => name.replaceAll('.', '/');

  static bool _isClass(ArchiveFile file) =>
      file.isFile && p.posix.extension(file.name) == '.class';
}
