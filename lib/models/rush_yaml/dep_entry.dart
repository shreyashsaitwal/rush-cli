part of 'rush_yaml.dart';

@JsonSerializable(
  anyMap: true,
  checked: true,
  disallowUnrecognizedKeys: true,
)
class DepEntry {
  final String? compile;
  final String? runtime;
  final List<String>? ignore;

  DepEntry({this.runtime, this.compile, this.ignore}) {
    if (runtime != null && compile != null) {
      throw Exception('Both compile and runtime are defined');
    }
  }

  factory DepEntry.fromJson(Map<String, dynamic> json) =>
      _$DepEntryFromJson(json);

  Map<String, dynamic> toJson() => _$DepEntryToJson(this);

  String get value => runtime ?? compile!;

  DependencyScope get scope =>
      runtime != null ? DependencyScope.runtime : DependencyScope.compile;

  bool get isRemote => value.contains(':');
}
