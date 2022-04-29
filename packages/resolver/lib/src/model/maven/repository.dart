import 'package:freezed_annotation/freezed_annotation.dart';

part 'repository.freezed.dart';

@freezed
class Repository with _$Repository {
  const factory Repository({
    required String id,
    required String name,
    required String url,
  }) = _Repository;
}