class FetchError {
  final String message;
  final String repositoryId;
  final int responseCode;
  final String file;

  const FetchError({
    required this.message,
    required this.repositoryId,
    required this.responseCode,
    required this.file,
  });
}
