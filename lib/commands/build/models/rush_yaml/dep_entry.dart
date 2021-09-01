part of 'rush_yaml.dart';

enum DepScope { implement, compileOnly }

extension DepScopeExt on DepScope {
  String value() {
    if (this == DepScope.implement) {
      return 'runtime';
    }
    return 'compile';
  }
}

@JsonSerializable(
  anyMap: true,
  checked: true,
  disallowUnrecognizedKeys: true,
)
class DepEntry {
  @JsonKey(name: 'compile_only')
  final String? compileOnly;
  final String? implement;
  final List<String>? exclude;

  DepEntry({this.implement, this.compileOnly, this.exclude}) {
    if (implement != null && compileOnly != null) {
      throw Exception('Can\'t implement and compile at the same time');
    }
  }

  factory DepEntry.fromJson(Map<String, dynamic> json) => _$DepEntryFromJson(json);

  Map<String, dynamic> toJson() => _$DepEntryToJson(this);

  String value() {
    if (implement != null) {
      return implement!;
    }
    return compileOnly!;
  }

  DepScope scope() {
    if (implement != null) {
      return DepScope.implement;
    }
    return DepScope.compileOnly;
  }
}
