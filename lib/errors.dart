class ProcessStartException implements Exception {
  final String message;
  const ProcessStartException(this.message);

  @override
  String toString() => 'ProcessStartException: $message';
}
