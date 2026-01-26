import 'package:rush/src/commander.dart';

void main(List<String> arguments) async {
  // TODO: handle thrown exceptions with a try-catch
  await Commander().run(arguments);
}
