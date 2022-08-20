import 'package:hive/hive.dart';

part 'build_box.g.dart';

@HiveType(typeId: 0)
class BuildBox {
  // This field stores the last time when the Android manifests from all the
  // AAR dependencies were successfully merged with the main manifest.
  @HiveField(0)
  DateTime _lastManifestMergeTime = DateTime.now();

  DateTime get lastManifestMergeTime => _lastManifestMergeTime;

  BuildBox update({DateTime? lastManifestMergeTime}) {
    if (lastManifestMergeTime != null) {
      _lastManifestMergeTime = lastManifestMergeTime;
    }
    return this;
  }
}
