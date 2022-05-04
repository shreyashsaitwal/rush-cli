import 'package:resolver/src/model/maven/repository.dart';

class Repositories {
  static const Set<Repository> defaultRepositories = {
    Repositories.googleAndroid,
    Repositories.mavenCentral
  };

  static const Repository googleAndroid = Repository(
      id: 'google-android',
      name: 'Google Android',
      url: 'https://dl.google.com/dl/android/maven2');

  static const Repository mavenCentral = Repository(
      id: 'central',
      name: 'Maven Central',
      url: 'https://repo.maven.apache.org/maven2');

  static const Repository googleMavenCentral = Repository(
      id: 'google-maven-central',
      name: 'Google Maven Central',
      url:
          'https://maven-central.storage-download.googleapis.com/repos/central/data');

  // TODO: Add more repositories
}
