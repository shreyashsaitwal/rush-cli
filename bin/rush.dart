import 'package:args/command_runner.dart';
import 'package:get_it/get_it.dart';
import 'package:rush/src/command_runner.dart';
import 'package:rush/src/services/logger.dart';
import 'package:rush/src/services/service_locator.dart';

Future<void> main(List<String> args) async {
  ServiceLocator.setupServiceLocator();
  await GetIt.I.allReady();
  try {
    await RushCommandRunner().run(args);
  } on UsageException catch (e) {
    GetIt.I<Logger>().err(e.message);
  }
}
