import 'package:rush/src/exceptions/rush_exception.dart';

class CliUsageException extends RushException {
  final String _message;

  @override
  String get message => _message;

  CliUsageException(this._message);
}
