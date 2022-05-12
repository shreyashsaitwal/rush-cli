import 'package:hive/hive.dart';

part 'build_box.g.dart';

@HiveType(typeId: 0)
class BuildBox extends HiveObject {
  // This field stores the last time when the Andriud manifests from all the
  // AAR dependencies were successfully merged with the main manifest.
  @HiveField(0)
  DateTime _lastManifestMergeTime = DateTime.now();

  // The arguments passed to the Kotlin annotation processor tool, kapt, need to
  // be obtained from a Kotlin program. This process is expensive and so we
  // cache the result for the subsequent builds.
  @HiveField(1)
  Map<String, String> _kaptOpts = {};

  // TODO: Storing this in box is not a good idea. A singleton would be better.
  // We run Kapt in parallel with kotlinc to reduce the build time. When the
  // extension source code has errors/warnings, they get printed twice, so, we
  // keep track of the already printed messages, and skip them if they show up
  // again during the same build.
  @HiveField(2)
  List<String> _previouslyLoggedLines = [];

  DateTime get lastManifestMergeTime => _lastManifestMergeTime;
  Map<String, String> get kaptOpts => _kaptOpts;
  List<String> get previouslyLoggedLines => _previouslyLoggedLines;

  BuildBox update({
    DateTime? lastResolutionTime,
    Set<String>? dependencyPaths,
    DateTime? lastManifestMergeTime,
    Map<String, String>? kaptOpts,
    List<String>? previouslyLoggedLines,
  }) {
    if (lastManifestMergeTime != null) {
      _lastManifestMergeTime = lastManifestMergeTime;
    }

    if (kaptOpts != null) {
      _kaptOpts = kaptOpts;
    }

    if (previouslyLoggedLines != null) {
      _previouslyLoggedLines = previouslyLoggedLines;
    }

    return this;
  }
}
