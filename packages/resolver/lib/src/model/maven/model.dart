import 'package:freezed_annotation/freezed_annotation.dart';

part 'model.freezed.dart';
part 'model.g.dart';

@freezed
class Model with _$Model {
  const factory Model({
    required String groupId,
    required String artifactId,
    required String version,
    required String name,
    @Default('jar') String packaging,
    @Default('') String description,
    @Default('') String url,
    @Default(Dependencies()) Dependencies dependencies,
  }) = _Model;

  factory Model.fromJson(Map<String, dynamic> json) => _$ModelFromJson(json);
}

@freezed
class Dependencies with _$Dependencies {
  const factory Dependencies({
    @Default([]) List<Dependency> dependencies,
  }) = _Dependencies;

  factory Dependencies.fromJson(Map<String, dynamic> json) => _$DependenciesFromJson(json);
}

@freezed
class Dependency with _$Dependency {
  const factory Dependency({
    required String groupId,
    required String artifactId,
    required String version,
    required String classifier,
    @Default('jar') String packaging,
    @Default(Scope.compile) Scope scope,
    @Default(false) bool optional,
  }) = _Dependency;

  factory Dependency.fromJson(Map<String, dynamic> json) =>
      _$DependencyFromJson(json);
}

enum Scope {
  compile,
  provided,
  runtime,
  test,
}
