import 'dart:io' show Platform;

import 'package:archive/archive.dart';
import 'package:get_it/get_it.dart';
import 'package:path/path.dart' as p;
import 'package:pool/pool.dart';

import 'package:rush/src/commands/build/aix.dart';
import 'package:rush/src/commands/build/android_keep_rules.dart';
import 'package:rush/src/commands/build/library_plan.dart';
import 'package:rush/src/commands/build/private_names.dart';
import 'package:rush/src/commands/build/program_split.dart';
import 'package:rush/src/commands/build/relocation.dart';
import 'package:rush/src/commands/build/tools/executor.dart';
import 'package:rush/src/config/config.dart';
import 'package:rush/src/services/file_service.dart';
import 'package:rush/src/utils/file_extension.dart';
import 'package:rush/src/utils/zip.dart';

final _fs = GetIt.I<FileService>();

class PrivateLibraries {
  PrivateLibraries._(this._config, this._plan, this._aars);

  static Future<PrivateLibraries> prepare(
          Config config, LibraryPlan plan) async =>
      PrivateLibraries._(config, plan, {
        for (final aar in plan.privateAars) aar: await _archive(aar.file),
      });

  final Config _config;
  final LibraryPlan _plan;
  final Map<ResolvedLibrary, Archive> _aars;

  bool get isEmpty => _plan.privateJars.isEmpty && _aars.isEmpty;

  Iterable<String> get aarClasses => _aars.keys.map((el) => el.classesJar);

  Future<String> keepRules(
      Iterable<String> program, List<Map<String, dynamic>> buildInfos) async {
    final rules = p.join(_fs.buildFilesDir.path, 'private-libraries.pro');
    await rules.asFile().writeAsString(androidKeepRules(
          programClasses: {
            for (final jar in program)
              for (final name in await _classes(jar)) name.replaceAll('/', '.'),
          },
          aars: _aars.values,
          manifestElements: [
            for (final info in buildInfos)
              if (info['activities'] case final List<dynamic> elements)
                ...elements.cast<String>(),
          ],
        ));
    return rules;
  }

  Future<PrivateProgram> split(String output,
      {required String mapping,
      required String artJarPath,
      required String package}) async {
    final aarOf = {
      for (final aar in _aars.keys)
        for (final name in await _classes(aar.classesJar))
          name: aar.aarFileName,
    };
    final privateClasses = {
      ...aarOf.keys,
      for (final jar in _plan.privateJars) ...await _classes(jar),
    };
    final split = ProgramSplit(await _archive(output),
        mapping: await mapping.asFile().readAsString(),
        aarOf: aarOf,
        privateClasses: privateClasses);
    await writeZip(artJarPath, split.runtime);
    return PrivateProgram._(
      _config,
      _plan.libraryJars,
      PrivateNames(
        package: package,
        classes: {...privateClasses, ...split.privateClasses},
        aars: {
          for (final MapEntry(key: aar, value: archive) in _aars.entries)
            aar.aarFileName: archive,
        },
      ),
      _aars,
      {
        for (final aar in _aars.keys)
          if (split.aars[aar.aarFileName] case final classes?)
            aar: await _written(_shrunkClasses(aar), classes),
      },
    );
  }

  String _shrunkClasses(ResolvedLibrary aar) =>
      _privateAarFile(aar, 'shrunk.jar');

  static Future<String> _written(
      String path, Iterable<ArchiveFile> entries) async {
    await writeZip(path, entries);
    return path;
  }

  static Future<Set<String>> _classes(String jar) async =>
      relocatableClasses((await _archive(jar))
          .files
          .where((el) => el.isFile)
          .map((el) => el.name)).toSet();
}

class PrivateProgram {
  PrivateProgram._(this._config, this._libraryJars, this.names, this._aars,
      this._shrunkAars);

  PrivateProgram.none(Config config, String package)
      : this._(config, {},
            PrivateNames(package: package, classes: {}, aars: {}), {}, {});

  final Config _config;
  final Set<String> _libraryJars;
  final PrivateNames names;
  final Map<ResolvedLibrary, Archive> _aars;
  final Map<ResolvedLibrary, String> _shrunkAars;

  late final Future<String> _spec = _writeSpec();

  Iterable<String> get relocatedAarClasses =>
      _shrunkAars.keys.map(_relocatedClasses);

  Future<List<Library>> packageAars(String artJarPath) async {
    for (final MapEntry(key: aar, value: classes) in _shrunkAars.entries) {
      await relocate(classes, _relocatedClasses(aar));
    }
    final classpath = {..._libraryJars, artJarPath, ...relocatedAarClasses};
    final pool = Pool(Platform.numberOfProcessors.clamp(1, 4));
    return Future.wait([
      for (final aar in _aars.keys)
        pool.withResource(() => _packageAar(aar, classpath)),
    ]);
  }

  Future<void> relocate(String input, String output) async =>
      Executor.execRelocator(input: input, output: output, spec: await _spec);

  Future<String> _writeSpec() async {
    final spec = p.join(_fs.buildFilesDir.path, 'relocation.txt');
    await spec.asFile().writeAsString(names.relocationSpec);
    return spec;
  }

  Future<Library> _packageAar(
      ResolvedLibrary aar, Set<String> classpath) async {
    final renamed = names.renameAar(_aars[aar]!,
        classes: _shrunkAars.containsKey(aar)
            ? await _desugaredClasses(aar, classpath)
            : null);
    return Library(names.aarFileName(aar.aarFileName), zipBytes(renamed.files));
  }

  Future<List<int>> _desugaredClasses(
      ResolvedLibrary aar, Set<String> classpath) async {
    final relocated = _relocatedClasses(aar);
    final desugared = _privateAarFile(aar, 'desugared.jar');
    await Executor.execDesugar(_config,
        input: relocated,
        output: desugared,
        classpathJars: {...classpath}..remove(relocated));
    return desugared.asFile().readAsBytes();
  }

  String _relocatedClasses(ResolvedLibrary aar) =>
      _privateAarFile(aar, 'relocated.jar');
}

String _privateAarFile(ResolvedLibrary aar, String suffix) => p.join(
    p.join(_fs.buildFilesDir.path, 'private-aars').asDir(true).path,
    '${aar.aarFileName}.$suffix');

Future<Archive> _archive(String path) async =>
    ZipDecoder().decodeBytes(await path.asFile().readAsBytes());
