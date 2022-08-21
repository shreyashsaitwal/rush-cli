import 'package:get_it/get_it.dart';

import './libs_service.dart';
import './file_service.dart';
import './logger.dart';

void setupServiceLocator(String cwd) {
  GetIt.I
    ..registerLazySingleton<FileService>(() => FileService(cwd))
    ..registerLazySingleton<Logger>(() => Logger())
    ..registerLazySingletonAsync<LibService>(
        () => LibService.instantiate());
}
