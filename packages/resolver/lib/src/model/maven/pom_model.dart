import 'dart:convert';

import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:xml2json/xml2json.dart';

part 'pom_model.freezed.dart';
part 'pom_model.g.dart';

@freezed
class PomModel with _$PomModel {
  const factory PomModel({
    required String groupId,
    required String artifactId,
    required String version,
    required String name,
    @Default('jar') String packaging,
    @Default('') String description,
    @Default('') String url,
    @JsonKey(fromJson: PomModel._depFromJson)
    @Default([])
        List<Dependency> dependencies,
  }) = _Model;

  factory PomModel.fromJson(Map<String, dynamic> json) =>
      _$PomModelFromJson(json);

  factory PomModel.fromXml(String xmlString) {
    final transformer = Xml2Json()..parse(xmlString);
    final json = jsonDecode(transformer.toParker());
    return PomModel.fromJson(json['project']);
  }

  static List<Dependency> _depFromJson(Map<String, dynamic> json) {
    final deps = <Dependency>[];
    final jsonDeps = json['dependency'];

    // If the artifact has only one dep, it will be decoded as a map instead of
    // a list.
    if (jsonDeps is Map) {
      deps.add(Dependency.fromJson(jsonDeps as Map<String, dynamic>));
    } else {
      for (final dep in jsonDeps) {
        deps.add(Dependency.fromJson(dep));
      }
    }
    return deps;
  }
}

@freezed
class Dependency with _$Dependency {
  const factory Dependency({
    required String groupId,
    required String artifactId,
    required String version,
    @Default('jar') String packaging,
    @Default(DependencyScope.compile) DependencyScope scope,
    @Default(false) bool optional,
  }) = _Dependency;

  factory Dependency.fromJson(Map<String, dynamic> json) =>
      _$DependencyFromJson(json);
}

enum DependencyScope {
  compile,
  provided,
  runtime,
  test,
}
