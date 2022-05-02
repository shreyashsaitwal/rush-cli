import 'dart:io';

import 'package:resolver/resolver.dart';

Future<void> main(List<String> args) async {
  final coordinate = 'org.hamcrest:hamcrest-core:1.3';
  final resolver = ArtifactResolver();
  final resolvedArtifact = await resolver.resolvePom(coordinate);
  await resolver.download(resolvedArtifact, downloadSources: true);

  if (File(resolvedArtifact.main.localFile).existsSync()) {
    print('Downloaded ${resolvedArtifact.main.localFile}');
  } else {
    print('Failed to download ${resolvedArtifact.main.localFile}');
  }
}