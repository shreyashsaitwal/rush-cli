import 'package:archive/archive.dart';
import 'package:get_it/get_it.dart';
import 'package:path/path.dart' as p;

import 'package:rush/src/commands/build/aix.dart';
import 'package:rush/src/commands/build/library_plan.dart';
import 'package:rush/src/commands/build/private_names.dart';
import 'package:rush/src/commands/build/relocation.dart';
import 'package:rush/src/commands/build/tools/executor.dart';
import 'package:rush/src/commands/build/tools/library_desugarer.dart';
import 'package:rush/src/config/config.dart';
import 'package:rush/src/services/file_service.dart';
import 'package:rush/src/utils/file_extension.dart';
import 'package:rush/src/utils/zip.dart';

final _fs = GetIt.I<FileService>();

class PrivateLibraries {
  PrivateLibraries._(this.names, this._desugaredAars, this._spec);

  static Future<PrivateLibraries> prepare(
      Config config, LibraryPlan plan, String package) async {
    final desugarer = LibraryDesugarer(config);
    final aarClasses = {for (final aar in plan.privateAars) aar.classesJar};
    final desugaredAars = <ResolvedLibrary, String>{
      for (final aar in plan.privateAars)
        aar: await desugarer.desugar(
          aar.aarFileName,
          input: aar.classesJar,
          classpathJars: {
            ...plan.libraryJars,
            ...plan.privateJars,
            ...aarClasses,
          }..remove(aar.classesJar),
        ),
    };
    final names = PrivateNames(
      package: package,
      classes: {
        for (final jar in [...plan.privateJars, ...desugaredAars.values])
          ...relocatableClasses(await _entries(jar)),
      },
      aars: {
        for (final aar in plan.privateAars)
          aar.aarFileName: await _archive(aar.file),
      },
    );
    final spec = p.join(_fs.buildFilesDir.path, 'relocation.txt').asFile();
    await spec.writeAsString(names.relocationSpec);
    return PrivateLibraries._(names, desugaredAars, spec.path);
  }

  final PrivateNames names;
  final Map<ResolvedLibrary, String> _desugaredAars;
  final String _spec;

  Iterable<String> get originalAarClasses => _desugaredAars.values;

  Iterable<String> get relocatedAarClasses =>
      _desugaredAars.keys.map(_relocatedClasses);

  Future<List<Library>> packageAars() async => [
        for (final MapEntry(key: aar, value: classes) in _desugaredAars.entries)
          await _packageAar(aar, classes),
      ];

  Future<void> relocate(String input, String output) =>
      Executor.execRelocator(input: input, output: output, spec: _spec);

  Future<Library> _packageAar(ResolvedLibrary aar, String classes) async {
    final relocated = _relocatedClasses(aar);
    p.dirname(relocated).asDir(true);
    await relocate(classes, relocated);
    final renamed = names.renameAar(await _archive(aar.file),
        classes: await relocated.asFile().readAsBytes());
    return Library(names.aarFileName(aar.aarFileName), zipBytes(renamed.files));
  }

  String _relocatedClasses(ResolvedLibrary aar) =>
      p.join(_fs.buildFilesDir.path, 'private-aars', '${aar.aarFileName}.jar');

  static Future<Archive> _archive(String path) async =>
      ZipDecoder().decodeBytes(await path.asFile().readAsBytes());

  static Future<Iterable<String>> _entries(String jar) async =>
      (await _archive(jar)).files.where((el) => el.isFile).map((el) => el.name);
}
