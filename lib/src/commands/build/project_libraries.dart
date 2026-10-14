import 'dart:io' show File;

import 'package:get_it/get_it.dart';

import 'package:rush/src/commands/build/library_plan.dart';
import 'package:rush/src/config/config.dart';
import 'package:rush/src/resolver/artifact.dart';
import 'package:rush/src/services/ai2_runtime.dart';
import 'package:rush/src/services/file_service.dart';
import 'package:rush/src/services/lib_service.dart';
import 'package:rush/src/utils/file_extension.dart';

final _fs = GetIt.I<FileService>();
final _component =
    RegExp(r'<(activity|activity-alias|service|receiver|provider)[\s>]');
final _manifestPackage = RegExp(r'<manifest[^>]*\spackage\s*=\s*"([^"]+)"');

Future<LibraryPlan> planProjectLibraries(
    LibService libService, Config config) async {
  final runtime = await Ai2Runtime.load();
  final conditional =
      {...runtime.libs}.difference({...runtime.alwaysIncludedLibs});
  return planLibraries(
    dependencies:
        await _resolved(await libService.extensionDependencies(config)),
    appInventor:
        await _resolved(await libService.providedDependencies(), conditional),
    placements: config.libraries,
  );
}

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
    originalContents: isAar ? await _originalContents(artifact) : const {},
  );
}

Future<Set<OriginalContent>> _originalContents(Artifact aar) async => {
      if (await _hasFiles(aar, 'res') || await _hasSymbols(aar))
        OriginalContent.resources,
      if (await _hasFiles(aar, 'assets')) OriginalContent.assets,
      if (await _hasFiles(aar, 'jni')) OriginalContent.nativeLibraries,
      if (await _declaresComponents(aar)) OriginalContent.components,
    };

Future<bool> _hasFiles(Artifact aar, String directory) async {
  final dir =
      _fs.resourceFromExtractedAar(aar.artifactFile, directory).path.asDir();
  return await dir.exists() &&
      await dir.list(recursive: true).any((el) => el is File);
}

Future<bool> _hasSymbols(Artifact aar) async {
  final symbols = _fs.resourceFromExtractedAar(aar.artifactFile, 'R.txt');
  return await symbols.exists() &&
      (await symbols.readAsString()).trim().isNotEmpty;
}

Future<bool> _declaresComponents(Artifact aar) async {
  final manifest =
      _fs.resourceFromExtractedAar(aar.artifactFile, 'AndroidManifest.xml');
  return await manifest.exists() &&
      _component.hasMatch(await manifest.readAsString());
}

Future<String?> _package(String manifest) async => _manifestPackage
    .firstMatch(await manifest.asFile().readAsString())
    ?.group(1);

Future<String?> _extracted(Artifact aar, String fileName) async {
  final file = _fs.resourceFromExtractedAar(aar.artifactFile, fileName);
  return await file.exists() ? file.path : null;
}
