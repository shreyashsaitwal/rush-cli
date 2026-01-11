/// Example: Resolve and download real Maven dependencies from Maven Central.
///
/// This example demonstrates:
/// 1. Setting up local and remote repositories
/// 2. Resolving a dependency tree from Maven Central
/// 3. Downloading JARs to local cache
/// 4. Building a classpath from resolved artifacts
///
/// Usage:
///   dart run example/maven_resolver_example.dart [groupId] [artifactId] [version]
///
/// Examples:
///   dart run example/maven_resolver_example.dart
///   dart run example/maven_resolver_example.dart com.google.guava guava 32.1.3-jre
///   dart run example/maven_resolver_example.dart org.slf4j slf4j-api 2.0.9
///   dart run example/maven_resolver_example.dart com.fasterxml.jackson.core jackson-databind 2.15.3
library;

import 'dart:io';

import 'package:maven_resolver/maven_resolver.dart';

Future<void> main(List<String> args) async {
  print('Maven Resolver - Real Dependency Resolution Example\n');

  // Parse command line args or use defaults
  final groupId = args.isNotEmpty ? args[0] : 'com.google.guava';
  final artifactId = args.length > 1 ? args[1] : 'guava';
  final version = args.length > 2 ? args[2] : '32.1.3-jre';

  print('Resolving: $groupId:$artifactId:$version\n');

  // Set up the local repository (~/.m2/repository)
  final localRepo = LocalRepository.defaultLocation();
  print('Local repository: ${localRepo.repositoryPath}');

  // Set up Maven Central as the remote repository
  final mavenCentral = RemoteRepository(
    id: 'central',
    url: 'https://repo1.maven.org/maven2',
    localCache: localRepo,
  );

  // Set up Google Maven repository (for Android dependencies)
  final googleMaven = RemoteRepository(
    id: 'google',
    url: 'https://maven.google.com',
    localCache: localRepo,
  );

  // Create a composite repository that checks local first, then remote
  final repository = CompositeRepository([
    localRepo,
    mavenCentral,
    googleMaven,
  ]);

  // Create the resolver with compile scope
  final resolver = DependencyResolver(
    repository: repository,
    config: const ResolverConfig(
      scopes: {DependencyScope.compile, DependencyScope.runtime},
      failOnMissing: false,
    ),
  );

  try {
    // Define the dependency to resolve
    final dependency = Dependency(
      groupId: groupId,
      artifactId: artifactId,
      version: version,
    );

    print('\n--- Resolving Dependency Tree ---\n');

    final stopwatch = Stopwatch()..start();

    // Resolve the full dependency tree
    final result = await resolver.resolve(
      directDependencies: [dependency],
    );

    stopwatch.stop();
    print('Resolution completed in ${stopwatch.elapsedMilliseconds}ms\n');

    // Print results as a tree
    print('Resolved ${result.artifacts.length} artifacts:\n');

    for (final artifact in result.artifacts) {
      final indent = '  ' * (artifact.depth - 1);
      final marker = artifact.depth == 1 ? '+' : '\\-';
      print('$indent$marker ${artifact.coordinate} [${artifact.scope.name}]');
    }

    // Print conflicts if any
    if (result.conflicts.isNotEmpty) {
      print('\n--- Version Conflicts Resolved ---\n');
      for (final conflict in result.conflicts) {
        print('${conflict.artifactKey}:');
        print(
          '  Selected: ${conflict.selectedVersion} (${conflict.reason.name})',
        );
        print('  Rejected: ${conflict.conflictingVersions.join(", ")}');
      }
    }

    // Print errors if any
    if (result.errors.isNotEmpty) {
      print('\n--- Errors ---\n');
      for (final error in result.errors) {
        print('  - ${error.message}');
      }
    }

    // Download artifacts and collect paths
    print('\n--- Downloading Artifacts ---\n');

    final downloadedPaths = <String>[];
    var totalSize = 0;

    for (final artifact in result.artifacts) {
      final coord = artifact.coordinate;

      // Skip POM-only artifacts
      if (coord.packaging == 'pom') {
        print('  [skip] ${coord.artifactId} (pom-only)');
        continue;
      }

      // Fetch the artifact (will download if not cached)
      final fetchResult = await repository.fetchArtifact(coord);

      if (fetchResult != null) {
        // Construct the local path
        final localPath =
            '${localRepo.repositoryPath}/${coord.artifactFilePath()}';
        downloadedPaths.add(localPath);

        final file = File(localPath);
        if (await file.exists()) {
          final size = await file.length();
          totalSize += size;
          final cached = fetchResult.fromCache ? '(cached)' : '(downloaded)';
          print(
              '  [ok] ${coord.artifactId}-${coord.version}.${coord.packaging} '
              '${_formatSize(size)} $cached');
        } else {
          print(
              '  [ok] ${coord.artifactId}-${coord.version}.${coord.packaging}');
        }
      } else {
        print(
            '  [miss] ${coord.artifactId}-${coord.version}.${coord.packaging} (not found)');
      }
    }

    print('\nTotal size: ${_formatSize(totalSize)}');
    print('Artifacts downloaded to: ${localRepo.repositoryPath}');

    // Generate classpath
    if (downloadedPaths.isNotEmpty) {
      print('\n--- Classpath ---\n');

      final separator = Platform.isWindows ? ';' : ':';
      final classpath = downloadedPaths.join(separator);

      // Print abbreviated classpath
      if (classpath.length > 200) {
        print('CLASSPATH="${classpath.substring(0, 200)}..."');
        print('\n(${downloadedPaths.length} JARs total)');
      } else {
        print('CLASSPATH="$classpath"');
      }

      // Show usage example
      print('\n--- Usage Example ---\n');
      print('# Set the classpath:');
      print('export CLASSPATH="$classpath"');
      print('\n# Compile Java code with these dependencies:');
      print('javac -cp "\$CLASSPATH" YourApp.java');
      print('\n# Run Java code:');
      print('java -cp "\$CLASSPATH:." YourApp');
    }

    // Summary
    print('\n--- Summary ---\n');
    print('Artifact: $groupId:$artifactId:$version');
    print('Direct dependencies: 1');
    print('Transitive dependencies: ${result.artifacts.length - 1}');
    print('Conflicts resolved: ${result.conflicts.length}');
    print('Errors: ${result.errors.length}');
  } catch (e, st) {
    print('\nError: $e');
    print('\nStack trace:\n$st');
    exit(1);
  } finally {
    await repository.close();
  }
}

/// Formats a file size in human-readable format.
String _formatSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
