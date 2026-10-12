String errorMessage(Object error) {
  final message = error.toString();
  return message.startsWith('Exception: ')
      ? message.substring('Exception: '.length)
      : message;
}
