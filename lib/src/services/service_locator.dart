import 'dart:io';

import 'package:get_it/get_it.dart';

import 'lib_service.dart';
import './file_service.dart';
import './logger.dart';

class ServiceLocator {
  static void setupServiceLocator() {
    GetIt.I
      ..registerLazySingleton<FileService>(
          () => FileService(Directory.current.path))
      ..registerLazySingleton<Logger>(() => Logger())
      ..registerLazySingletonAsync<LibService>(() => LibService.instantiate());
  }
}
