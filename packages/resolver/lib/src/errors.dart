import 'package:resolver/src/model/file_spec.dart';

class FetchError {
  final String message;
  final String repositoryId;
  final int responseCode;
  final FileSpec fileSpec;

  const FetchError({
    required this.message,
    required this.repositoryId,
    required this.responseCode,
    required this.fileSpec,
  });

  @override
  String toString() => '''
FetchError {
  message: $message,
  repositoryId: $repositoryId,
  responseCode: $responseCode,
  file: $fileSpec,
}''';
}
