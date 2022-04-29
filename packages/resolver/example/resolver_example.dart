import 'package:resolver/resolver.dart';
import 'package:resolver/src/artifact_fetcher.dart';
Future<void> main() async {
  final res = ArtifactResolver();
  final artifact = res.artifactFor('androidx.work:work-runtime:2.6.0');
  await res.resolve(artifact);
}
