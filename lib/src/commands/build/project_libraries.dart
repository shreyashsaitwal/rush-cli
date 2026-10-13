import 'package:get_it/get_it.dart';

import 'package:rush/src/commands/build/library_plan.dart';
import 'package:rush/src/config/config.dart';
import 'package:rush/src/resolver/artifact.dart';
import 'package:rush/src/services/ai2_runtime.dart';
import 'package:rush/src/services/file_service.dart';
import 'package:rush/src/services/lib_service.dart';
import 'package:rush/src/utils/file_extension.dart';

final _fs = GetIt.I<FileService>();
final _manifestPackage = RegExp(r'<manifest[^>]*\spackage\s*=\s*"([^"]+)"');

Future<LibraryPlan> planProjectLibraries(
    LibService libService, Config config) async {
  final runtime = await Ai2Runtime.load();
  final conditional =
      {...runtime.libs}.difference({...runtime.alwaysIncludedLibs});
  return planLibraries(
    dependencies:
        await _resolved(await libService.extensionDependencies(config)),
    appInventor: await _resolved(
        await libService.providedDependencies(null), conditional),
    provided:
        await _resolved(await libService.projectProvidedDependencies(config)),
    providedWithDependencies: await _resolved(
        await libService.projectProvidedWithDependencies(config)),
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
  );
}

Future<String?> _package(String manifest) async => _manifestPackage
    .firstMatch(await manifest.asFile().readAsString())
    ?.group(1);

Future<String?> _extracted(Artifact aar, String fileName) async {
  final file = _fs.resourceFromExtractedAar(aar.artifactFile, fileName);
  return await file.exists() ? file.path : null;
}
