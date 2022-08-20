import 'package:get_it/get_it.dart';
import 'package:path/path.dart'as p;

import './libs_service.dart';
import './file_service.dart';
import './logger.dart';

void setupServiceLocator(String cwd, String rushHomeDir) {
  GetIt.I
    ..registerLazySingleton<FileService>(() => FileService(cwd, rushHomeDir))
    ..registerLazySingleton<Logger>(() => Logger())
    ..registerLazySingletonAsync<LibService>(
        () => LibService.instantiate(p.join(rushHomeDir, 'cache')));
}
