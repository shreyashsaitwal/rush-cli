# Maven Resolver

A Maven-compliant dependency resolver for Dart. This package implements Maven's dependency resolution algorithm, including version comparison, scope mediation, conflict resolution, and BOM processing.

## Features

- **Maven-compliant version comparison** - Ported from Maven's `ComparableVersion.java`
- **Version ranges** - Full support for Maven version range syntax
- **Dependency resolution** - BFS traversal with "nearest wins" conflict resolution
- **Scope mediation** - Correct transitive scope handling per Maven spec
- **BOM support** - Import BOMs and inherit dependency versions
- **Exclusions** - Per-dependency and global exclusions, including wildcards
- **SNAPSHOT resolution** - Resolves timestamped SNAPSHOT versions
- **Multiple packaging types** - Supports JAR, AAR, POM, and others

## Installation

```yaml
dependencies:
  maven_resolver:
    path: packages/maven_resolver
```

## Quick Start

```dart
import 'package:maven_resolver/maven_resolver.dart';

Future<void> main() async {
  // Create repositories
  final localRepo = LocalRepository();
  final centralRepo = RemoteRepository(
    id: 'central',
    url: 'https://repo.maven.apache.org/maven2',
  );

  // Composite repository tries local first, then remote
  final repository = CompositeRepository([localRepo, centralRepo]);

  // Create resolver
  final resolver = DependencyResolver(repository: repository);

  // Resolve dependencies
  final result = await resolver.resolve(
    directDependencies: [
      const Dependency(
        groupId: 'com.google.guava',
        artifactId: 'guava',
        version: '32.1.2-jre',
      ),
    ],
  );

  if (result.isSuccess) {
    for (final artifact in result.artifacts) {
      print('${artifact.coordinate} (${artifact.scope.name})');
    }
  } else {
    for (final error in result.errors) {
      print('Error: ${error.message}');
    }
  }

  // Clean up
  await repository.close();
}
```

## API Reference

### Repositories

#### LocalRepository

Reads artifacts from the local Maven cache (`~/.m2/repository`).

```dart
// Uses default ~/.m2/repository
final repo = LocalRepository();

// Custom path
final repo = LocalRepository(path: '/path/to/repo');
```

#### RemoteRepository

Fetches artifacts from a remote Maven repository with retry and caching support.

```dart
final repo = RemoteRepository(
  id: 'central',
  url: 'https://repo.maven.apache.org/maven2',
  // Optional configuration
  connectTimeout: Duration(seconds: 10),
  readTimeout: Duration(seconds: 30),
  maxRetries: 3,
  retryDelay: Duration(seconds: 1),
);
```

#### CompositeRepository

Tries multiple repositories in order until an artifact is found.

```dart
final repo = CompositeRepository([
  LocalRepository(),
  RemoteRepository(id: 'central', url: 'https://repo.maven.apache.org/maven2'),
  RemoteRepository(id: 'google', url: 'https://maven.google.com'),
]);
```

### Dependency Resolution

#### DependencyResolver

The main entry point for resolving dependencies.

```dart
final resolver = DependencyResolver(
  repository: repository,
  config: ResolverConfig(
    scopes: {DependencyScope.compile, DependencyScope.runtime},
    includeOptional: false,
    failOnMissing: false,
  ),
);

final result = await resolver.resolve(
  directDependencies: [...],
  dependencyManagement: [...],  // Optional version constraints
  exclusions: [...],            // Global exclusions
);
```

#### ResolverConfig

Configuration options for the resolver.

```dart
const config = ResolverConfig(
  // Which scopes to include in resolution
  scopes: {DependencyScope.compile, DependencyScope.runtime},
  
  // Whether to include optional transitive dependencies
  includeOptional: false,
  
  // Whether to fail on missing dependencies
  failOnMissing: false,
);
```

#### ResolutionResult

The result of dependency resolution.

```dart
final result = await resolver.resolve(...);

// Check for success
if (result.isSuccess) {
  // All resolved artifacts
  final all = result.artifacts;
  
  // Filter by scope
  final compile = result.compileArtifacts;
  final runtime = result.runtimeArtifacts;
  final test = result.testArtifacts;
}

// Check for errors
for (final error in result.errors) {
  print('${error.coordinate}: ${error.message}');
}

// Check for version conflicts
for (final conflict in result.conflicts) {
  print('${conflict.artifactKey}: selected ${conflict.selectedVersion}, '
        'rejected ${conflict.conflictingVersions}');
}
```

### Dependencies

#### Dependency

Represents a Maven dependency declaration.

```dart
const dep = Dependency(
  groupId: 'com.example',
  artifactId: 'my-lib',
  version: '1.0.0',           // Optional if using dependencyManagement
  type: 'jar',                // Default: 'jar', also supports 'aar', 'pom', etc.
  classifier: 'sources',      // Optional classifier
  scope: DependencyScope.compile,
  optional: false,
  exclusions: [
    Exclusion(groupId: 'org.unwanted', artifactId: 'lib'),
  ],
);
```

#### DependencyScope

Maven dependency scopes with correct transitivity rules.

```dart
DependencyScope.compile   // Default, available everywhere
DependencyScope.provided  // Provided by runtime environment
DependencyScope.runtime   // Not needed for compilation
DependencyScope.test      // Only for testing
DependencyScope.system    // Explicit path to JAR
DependencyScope.import_   // BOM import (dependencyManagement only)
```

#### Exclusion

Exclude transitive dependencies.

```dart
// Exclude specific artifact
const exclusion = Exclusion(
  groupId: 'org.unwanted',
  artifactId: 'bad-lib',
);

// Wildcard: exclude all from a group
const groupExclusion = Exclusion(
  groupId: 'org.unwanted',
  artifactId: '*',
);

// Wildcard: exclude all transitives
const allExclusion = Exclusion.all;  // *:*
```

### Version Handling

#### MavenVersion

Maven-compliant version comparison.

```dart
final v1 = MavenVersion.parse('1.0.0');
final v2 = MavenVersion.parse('1.0.1');

print(v1 < v2);   // true
print(v1 == v2);  // false

// Qualifier ordering (lowest to highest):
// alpha < beta < milestone < rc/cr < snapshot < "" (release) < sp
final alpha = MavenVersion.parse('1.0.0-alpha');
final release = MavenVersion.parse('1.0.0');
print(alpha < release);  // true
```

#### VersionRange

Parse and match Maven version ranges.

```dart
// Soft requirement (hint, can be overridden)
final soft = VersionRange.parse('1.0.0');

// Hard requirements
final exact = VersionRange.parse('[1.0.0]');        // Exactly 1.0.0
final atLeast = VersionRange.parse('[1.0.0,)');     // >= 1.0.0
final lessThan = VersionRange.parse('(,2.0.0)');    // < 2.0.0
final range = VersionRange.parse('[1.0.0,2.0.0)'); // >= 1.0.0 && < 2.0.0

// Check if version matches
print(range.contains(MavenVersion.parse('1.5.0')));  // true

// Select best version from available versions
final versions = ['1.0.0', '1.5.0', '2.0.0']
    .map(MavenVersion.parse)
    .toList();
final best = range.selectBest(versions);  // 1.5.0
```

### Artifact Coordinates

#### ArtifactCoordinate

5-part Maven coordinates.

```dart
const coord = ArtifactCoordinate(
  groupId: 'com.example',
  artifactId: 'my-lib',
  version: '1.0.0',
  packaging: 'jar',       // Default: 'jar'
  classifier: 'sources',  // Optional
);

// Parse from string
final parsed = ArtifactCoordinate.parse('com.example:my-lib:1.0.0');
final withType = ArtifactCoordinate.parse('com.example:my-lib:aar:1.0.0');
final full = ArtifactCoordinate.parse('com.example:my-lib:jar:sources:1.0.0');

// Get repository paths
print(coord.artifactPath);     // com/example/my-lib/1.0.0
print(coord.pomPath);          // com/example/my-lib/1.0.0/my-lib-1.0.0.pom
print(coord.artifactFilePath()); // com/example/my-lib/1.0.0/my-lib-1.0.0.jar
```

### BOM (Bill of Materials)

Import a BOM to inherit dependency versions.

```dart
final result = await resolver.resolve(
  directDependencies: [
    // Version inherited from BOM
    const Dependency(
      groupId: 'org.springframework',
      artifactId: 'spring-core',
      // No version specified - comes from BOM
    ),
  ],
  dependencyManagement: [
    // Import Spring Boot BOM
    const Dependency(
      groupId: 'org.springframework.boot',
      artifactId: 'spring-boot-dependencies',
      version: '3.2.0',
      type: 'pom',
      scope: DependencyScope.import_,
    ),
  ],
);
```

### POM Parsing

#### PomParser

Parse POM XML files.

```dart
const parser = PomParser();

// Parse from string
final pom = parser.parseString(xmlContent);

// Access POM data
print(pom.groupId);
print(pom.artifactId);
print(pom.version);
print(pom.dependencies);
print(pom.dependencyManagement);
print(pom.properties);
print(pom.parent);
```

#### EffectivePomBuilder

Build effective POMs with parent chain resolution and property interpolation.

```dart
final builder = EffectivePomBuilder(repository: repository);
final context = ResolutionContext();

final effectivePom = await builder.build(
  ArtifactCoordinate.parse('com.example:my-lib:1.0.0'),
  context,
);

// Effective POM has:
// - Merged properties from parent chain
// - Interpolated values (${project.version}, etc.)
// - Merged dependencyManagement (including BOMs)
print(effectivePom.properties);
print(effectivePom.dependencyManagement);
```

### Fetching Artifacts

After resolution, fetch the actual artifact files.

```dart
final result = await resolver.resolve(...);

for (final artifact in result.artifacts) {
  // Fetch the artifact file (JAR, AAR, etc.)
  final fetchResult = await repository.fetchArtifact(artifact.coordinate);
  if (fetchResult != null) {
    final bytes = fetchResult.content;
    // Save to disk, extract, etc.
  }
  
  // Fetch sources JAR (if available)
  final sourcesCoord = artifact.coordinate.copyWith(classifier: 'sources');
  final sources = await repository.fetchArtifact(sourcesCoord);
}
```

## Packaging Types

The resolver supports all Maven packaging types. Common ones include:

| Type | Extension | Description |
|------|-----------|-------------|
| `jar` | `.jar` | Java archive (default) |
| `aar` | `.aar` | Android archive |
| `pom` | `.pom` | Project object model |
| `war` | `.war` | Web application archive |
| `bundle` | `.jar` | OSGi bundle |

```dart
// AAR dependency
const aarDep = Dependency(
  groupId: 'androidx.core',
  artifactId: 'core',
  version: '1.12.0',
  type: 'aar',
);
```

## Resolution Algorithm

The resolver implements Maven's dependency resolution algorithm:

1. **BFS Traversal** - Dependencies are resolved breadth-first
2. **Nearest Wins** - Conflicts are resolved by choosing the version closest to the root
3. **First Declaration Wins** - On depth tie, first declared dependency wins
4. **Scope Mediation** - Transitive scopes are mediated per Maven spec
5. **Exclusions** - Applied to entire subtrees
6. **Optional Filtering** - Optional transitives excluded by default

### Conflict Resolution Example

```
A -> B:1.0 -> C:1.0
A -> D:1.0 -> C:2.0
```

Both `C:1.0` and `C:2.0` are at depth 3. Since `B` is declared before `D`, `C:1.0` wins.

```
A -> B:1.0 -> C:1.0
A -> C:2.0
```

`C:2.0` is at depth 2, `C:1.0` is at depth 3. `C:2.0` wins (nearer).

## Error Handling

```dart
final result = await resolver.resolve(...);

// Resolution errors (missing POMs, parse errors, etc.)
for (final error in result.errors) {
  print('Coordinate: ${error.coordinate}');
  print('Message: ${error.message}');
  print('Cause: ${error.cause}');
}

// Version conflicts (informational)
for (final conflict in result.conflicts) {
  print('Artifact: ${conflict.artifactKey}');
  print('Selected: ${conflict.selectedVersion}');
  print('Rejected: ${conflict.conflictingVersions}');
}
```

## License

See the main project license.
