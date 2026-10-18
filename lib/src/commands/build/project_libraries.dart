import 'dart:io' show File;

import 'package:archive/archive.dart';
import 'package:get_it/get_it.dart';

import 'package:rush/src/commands/build/android_manifest.dart';
import 'package:rush/src/commands/build/library_plan.dart';
import 'package:rush/src/commands/build/native_names.dart';
import 'package:rush/src/commands/build/original_names.dart';
import 'package:rush/src/commands/build/relocation.dart';
import 'package:rush/src/config/config.dart';
import 'package:rush/src/resolver/artifact.dart';
import 'package:rush/src/services/ai2_runtime.dart';
import 'package:rush/src/services/file_service.dart';
import 'package:rush/src/services/lib_service.dart';
import 'package:rush/src/utils/file_extension.dart';

final _fs = GetIt.I<FileService>();

Future<LibraryPlan> planProjectLibraries(
    LibService libService, Config config) async {
  final runtime = await Ai2Runtime.load();
  final conditional =
      {...runtime.libs}.difference({...runtime.alwaysIncludedLibs});
  final plan = planLibraries(
    dependencies:
        await _resolved(await libService.extensionDependencies(config)),
    appInventor:
        await _resolved(await libService.providedDependencies(), conditional),
    placements: config.libraries,
  );
  final nativeAars = plan.private.where((el) => el.hasNativeLibraries);
  if (config.originalNames.isEmpty && nativeAars.isEmpty) return plan;
  final privateClasses = await _classesOf(plan.private);
  return plan.withProblems(originalNameProblems(
    originalNames: config.originalNames,
    privateClasses: privateClasses,
    nativeNames: {
      for (final aar in nativeAars)
        aar.coordinate: await _nativeNames(aar, privateClasses),
    },
  ));
}

Future<Set<String>> _nativeNames(
        ResolvedLibrary aar, Set<String> classes) async =>
    {
      await for (final file in _fs
          .resourceFromExtractedAar(aar.file, 'jni')
          .path
          .asDir()
          .list(recursive: true))
        if (file is File && file.path.endsWith('.so'))
          ...namedClasses(await file.readAsBytes(), classes),
    };

Future<Set<String>> _classesOf(Iterable<ResolvedLibrary> libraries) async => {
      for (final library in libraries.where((el) => el.hasCode))
        ...relocatableClasses(ZipDecoder()
            .decodeBytes(await library.classesJar.asFile().readAsBytes())
            .files
            .map((el) => el.name)),
    };

Future<List<ResolvedLibrary>> _resolved(List<Artifact> artifacts,
        [Set<Artifact> conditional = const {}]) =>
    Future.wait(artifacts
        .map((el) => _library(el, inEveryApp: !conditional.contains(el))));

Future<ResolvedLibrary> _library(Artifact artifact,
    {required bool inEveryApp}) async {
  final isAar = artifact.packaging == 'aar';
  final manifest =
      isAar ? await _extracted(artifact, 'AndroidManifest.xml') : null;
  return ResolvedLibrary(
    coordinate: artifact.coordinate,
    scope: LibraryScope.values.byName(artifact.scope.name),
    isAar: isAar,
    file: artifact.artifactFile,
    classesJar: artifact.classesJar,
    dependencies: artifact.dependencies,
    manifest: manifest,
    consumerRules: isAar ? await _extracted(artifact, 'proguard.txt') : null,
    package: manifest == null ? null : await _package(manifest),
    inEveryApp: inEveryApp,
    hasResources: isAar && await _hasResources(artifact),
    hasCode: !isAar || await artifact.classesJar.asFile().exists(),
    hasNativeLibraries: isAar && await _hasFiles(artifact, 'jni'),
    originalContents: isAar ? await _originalContents(artifact) : const {},
  );
}

Future<Set<OriginalContent>> _originalContents(Artifact aar) async => {
      if (await _hasFiles(aar, 'assets')) OriginalContent.assets,
      if (await _hasFiles(aar, 'libs')) OriginalContent.bundledJars,
    };

Future<bool> _hasResources(Artifact aar) async {
  final symbols = _fs.resourceFromExtractedAar(aar.artifactFile, 'R.txt');
  return await _hasFiles(aar, 'res') ||
      await symbols.exists() &&
          (await symbols.readAsString()).trim().isNotEmpty;
}

Future<bool> _hasFiles(Artifact aar, String directory) async {
  final dir =
      _fs.resourceFromExtractedAar(aar.artifactFile, directory).path.asDir();
  return await dir.exists() &&
      await dir.list(recursive: true).any((el) => el is File);
}

Future<String?> _package(String manifest) async =>
    manifestPackage(await manifest.asFile().readAsString());

Future<String?> _extracted(Artifact aar, String fileName) async {
  final file = _fs.resourceFromExtractedAar(aar.artifactFile, fileName);
  return await file.exists() ? file.path : null;
}
