import 'package:hive/hive.dart';

part 'build_box.g.dart';

@HiveType(typeId: 0)
class BuildBox extends HiveObject {
  @HiveField(0)
  final List<String> lastResolvedDeps;

  @HiveField(1)
  final DateTime lastResolution;

  @HiveField(2)
  final Map<String, String> kaptOpts;

  @HiveField(3)
  final List<String> previouslyLogged;

  @HiveField(4)
  final DateTime lastManifMerge;

  BuildBox({
    required this.lastResolvedDeps,
    required this.lastResolution,
    required this.kaptOpts,
    required this.previouslyLogged,
    required this.lastManifMerge,
  });
}

extension BuildBoxExtension on Box<BuildBox> {
  void updateLastResolvedDeps(List<String> newVal) {
    final old = getAt(0);
    putAt(
        0,
        BuildBox(
          lastResolvedDeps: newVal,
          lastResolution: old?.lastResolution ?? DateTime.now(),
          kaptOpts: old?.kaptOpts ?? <String, String>{'': ''},
          previouslyLogged: old?.previouslyLogged ?? <String>[''],
          lastManifMerge: old?.lastManifMerge ?? DateTime.now(),
        ));
  }

  void updateLastResolution(DateTime newVal) {
    final old = getAt(0);
    putAt(
        0,
        BuildBox(
          lastResolvedDeps: old?.lastResolvedDeps ?? <String>[''],
          lastResolution: newVal,
          kaptOpts: old?.kaptOpts ?? <String, String>{'': ''},
          previouslyLogged: old?.previouslyLogged ?? <String>[''],
          lastManifMerge: old?.lastManifMerge ?? DateTime.now(),
        ));
  }

  void updateKaptOpts(Map<String, String> newVal) {
    final old = getAt(0);
    putAt(
        0,
        BuildBox(
          lastResolvedDeps: old?.lastResolvedDeps ?? <String>[''],
          lastResolution: old?.lastResolution ?? DateTime.now(),
          kaptOpts: newVal,
          previouslyLogged: old?.previouslyLogged ?? <String>[''],
          lastManifMerge: old?.lastManifMerge ?? DateTime.now(),
        ));
  }

  void updatePreviouslyLogged(List<String> newVal) {
    final old = getAt(0);
    putAt(
        0,
        BuildBox(
          lastResolvedDeps: old?.lastResolvedDeps ?? <String>[''],
          lastResolution: old?.lastResolution ?? DateTime.now(),
          kaptOpts: old?.kaptOpts ?? <String, String>{'': ''},
          previouslyLogged: newVal,
          lastManifMerge: old?.lastManifMerge ?? DateTime.now(),
        ));
  }

  void updateLastManifMerge(DateTime newVal) {
    final old = getAt(0);
    putAt(
        0,
        BuildBox(
          lastResolvedDeps: old?.lastResolvedDeps ?? <String>[''],
          lastResolution: old?.lastResolution ?? DateTime.now(),
          kaptOpts: old?.kaptOpts ?? <String, String>{'': ''},
          previouslyLogged: old?.previouslyLogged ?? <String>[''],
          lastManifMerge: newVal,
        ));
  }
}
