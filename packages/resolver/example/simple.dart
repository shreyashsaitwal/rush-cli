import 'dart:io';

import 'package:resolver/resolver.dart';

Future<void> main(List<String> args) async {
  final coordinate = 'androidx.work:work-runtime:2.7.0';
  final resolver = ArtifactResolver(cacheDir: './cache');
  final resolvedArtifact =
      await resolver.resolve(coordinate, DependencyScope.runtime);
  await resolver.download(resolvedArtifact);
  await resolver.downloadSources(resolvedArtifact);

  if (File(resolvedArtifact.main.localFile).existsSync()) {
    print('Downloaded ${resolvedArtifact.main.localFile}');
  } else {
    print('Failed to download ${resolvedArtifact.main.localFile}');
  }
}
