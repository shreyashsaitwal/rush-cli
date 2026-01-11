# Maven Resolver Specification - Addendum

This addendum addresses gaps identified in the initial spec and plan.

---

## Addendum A: Concerns & Resolutions

### A.1 Phase Ordering Concern

**Concern**: POM parsing (Phase 3) depends on repository (Phase 2) to fetch parent POMs.

**Resolution**: Phase 3 can use a stub/mock repository initially. We'll structure Phase 3 to:
1. Write POM parsing logic that takes XML strings as input (no I/O)
2. Write interpolation logic with explicit parent POM parameters
3. Unit test with hardcoded POM strings from fixtures
4. Integration with real repository comes in Phase 4

This allows parallel development if needed:
```
Phase 2 (Repository) ──┐
                       ├──> Phase 4 (Resolution)
Phase 3 (POM Parsing) ─┘
```

### A.2 Scope Mediation - Missing `system` Scope

**Corrected Table**:

| Direct Scope ↓ \ Transitive Scope → | compile | provided | runtime | test | system |
|-------------------------------------|---------|----------|---------|------|--------|
| compile | compile | - | runtime | - | - |
| provided | provided | - | provided | - | - |
| runtime | runtime | - | runtime | - | - |
| test | test | - | test | - | - |
| system | system | - | system | - | - |

**Note**: `system` scope dependencies are NOT transitive (like `provided`). If artifact A (compile) depends on B (system), B is **omitted** from transitives.

### A.3 Property Resolution Order

**Clarification**: There are two different orderings that serve different purposes:

**1. Property Source Priority (where to look for `${x}`):**
```
1. Project-defined properties (<properties> section)
2. Parent POM properties (recursive)
3. project.* fields (${project.version}, etc.)
4. settings.* fields (from settings.xml)
5. env.* (environment variables)
6. Java system properties
```

**2. Property Inheritance (child vs parent):**
```
- Child POM properties OVERRIDE parent properties with same key
- This happens during effective POM construction, BEFORE interpolation
- Interpolation then uses the merged property map
```

**Implementation approach:**
```dart
Map<String, String> buildPropertyMap(Pom pom, List<Pom> parents) {
  final properties = <String, String>{};
  
  // Start with most distant ancestor (reverse order)
  for (final parent in parents.reversed) {
    properties.addAll(parent.properties);
  }
  
  // Child overwrites parent
  properties.addAll(pom.properties);
  
  return properties;
}
```

### A.4 Checksum Policy

**Explicit behavior definition:**

| Policy | On Checksum Failure |
|--------|---------------------|
| `fail` | Throw exception, abort resolution |
| `warn` | Log warning, continue with file |
| `ignore` | Silently continue with file |

**Default**: `warn` (matches Maven default)

**Implementation:**
```dart
enum ChecksumPolicy { fail, warn, ignore }

Future<File> fetchWithChecksum(
  String path,
  ChecksumPolicy policy,
) async {
  final file = await fetchFile(path);
  final checksum = await fetchChecksum(path);
  
  if (checksum == null) {
    if (policy == ChecksumPolicy.fail) {
      throw ChecksumMissingException(path);
    }
    _log.warn('No checksum available for $path');
    return file;
  }
  
  if (!await verifyChecksum(file, checksum)) {
    switch (policy) {
      case ChecksumPolicy.fail:
        throw ChecksumVerificationException(path);
      case ChecksumPolicy.warn:
        _log.warn('Checksum verification failed for $path');
        break;
      case ChecksumPolicy.ignore:
        break;
    }
  }
  
  return file;
}
```

### A.5 Parallel POM Fetches

**Strategy for Phase 2:**

```dart
class RemoteRepository implements Repository {
  final int maxConcurrentFetches;  // Default: 4
  
  // Semaphore to limit concurrent HTTP requests
  final _fetchSemaphore = Pool(maxConcurrentFetches);
  
  Future<File?> fetchPom(ArtifactCoordinate coord) {
    return _fetchSemaphore.withResource(() async {
      // Actual fetch logic
    });
  }
}
```

**Where parallelism is safe:**
- Fetching POMs of sibling dependencies
- Fetching artifact files after resolution is complete
- Fetching checksum files alongside main files

**Where parallelism is NOT safe:**
- Resolving same artifact from multiple code paths (use locks)
- Writing to same local cache file (use file locks or serialize)
- BOM import processing (must be sequential per-POM)

### A.6 5-Part Coordinates (classifier/packaging)

**Full coordinate format:**
```
groupId:artifactId:packaging:classifier:version
```

**Examples:**
- `com.google.guava:guava:jar:27.0-jre` (3-part, defaults)
- `org.apache.maven:maven-core:jar:3.6.0` (explicit jar)
- `com.example:lib:jar:sources:1.0` (with classifier)
- `com.example:lib:test-jar:tests:1.0` (test-jar packaging)

**Parsing logic:**
```dart
class ArtifactCoordinate {
  final String groupId;
  final String artifactId;
  final String version;
  final String packaging;    // Default: 'jar'
  final String? classifier;  // Default: null
  
  factory ArtifactCoordinate.parse(String coord) {
    final parts = coord.split(':');
    
    switch (parts.length) {
      case 3:
        // groupId:artifactId:version
        return ArtifactCoordinate(
          groupId: parts[0],
          artifactId: parts[1],
          version: parts[2],
          packaging: 'jar',
          classifier: null,
        );
      case 4:
        // groupId:artifactId:packaging:version
        // OR groupId:artifactId:version:classifier (legacy)
        // Disambiguate: if parts[2] looks like a version, it's legacy
        if (_looksLikeVersion(parts[2])) {
          return ArtifactCoordinate(
            groupId: parts[0],
            artifactId: parts[1],
            version: parts[2],
            packaging: 'jar',
            classifier: parts[3],
          );
        } else {
          return ArtifactCoordinate(
            groupId: parts[0],
            artifactId: parts[1],
            version: parts[3],
            packaging: parts[2],
            classifier: null,
          );
        }
      case 5:
        // groupId:artifactId:packaging:classifier:version
        return ArtifactCoordinate(
          groupId: parts[0],
          artifactId: parts[1],
          version: parts[4],
          packaging: parts[2],
          classifier: parts[3],
        );
      default:
        throw FormatException('Invalid coordinate: $coord');
    }
  }
}
```

---

## Addendum B: Missing Elements

### B.1 Relocation Handling

**What is it?**
POMs can declare `<distributionManagement><relocation>` to redirect resolution to different coordinates.

**POM structure:**
```xml
<distributionManagement>
  <relocation>
    <groupId>new.group</groupId>        <!-- Optional -->
    <artifactId>new-artifact</artifactId> <!-- Optional -->
    <version>2.0</version>               <!-- Optional -->
    <message>Moved to new.group</message> <!-- Optional -->
  </relocation>
</distributionManagement>
```

**Resolution behavior:**
1. Fetch POM for requested coordinates
2. Check for `<relocation>` element
3. If present:
   - Log warning with relocation message
   - Track relocation in result
   - Follow relocation to new coordinates
   - **Recursively** repeat until no relocation
4. Detect cycles using visited set

**Implementation:**
```dart
Future<ResolvedPom> resolvePom(ArtifactCoordinate coord) async {
  final visited = <String>{};
  var current = coord;
  final relocations = <Relocation>[];
  
  while (true) {
    final key = '${current.groupId}:${current.artifactId}:${current.version}';
    if (!visited.add(key)) {
      throw RelocationCycleException(visited);
    }
    
    final pom = await fetchAndParsePom(current);
    final relocation = pom.distributionManagement?.relocation;
    
    if (relocation == null) {
      return ResolvedPom(
        pom: pom,
        relocations: relocations,
        finalCoordinate: current,
      );
    }
    
    _log.warn('Artifact $current has been relocated to ${relocation.target}');
    if (relocation.message != null) {
      _log.warn('  Reason: ${relocation.message}');
    }
    
    relocations.add(relocation);
    current = ArtifactCoordinate(
      groupId: relocation.groupId ?? current.groupId,
      artifactId: relocation.artifactId ?? current.artifactId,
      version: relocation.version ?? current.version,
      packaging: current.packaging,      // Preserved
      classifier: current.classifier,    // Preserved
    );
  }
}
```

**What's preserved during relocation:**
- `classifier`
- `packaging` (extension)

**What can change:**
- `groupId`
- `artifactId`
- `version`

### B.2 SNAPSHOT Handling

**What is it?**
SNAPSHOT versions (e.g., `1.0-SNAPSHOT`) are development versions that can change. They require special resolution via `maven-metadata.xml`.

**Key concepts:**

| Aspect | Release | SNAPSHOT |
|--------|---------|----------|
| Stability | Immutable | Can change |
| Filename | `lib-1.0.jar` | `lib-1.0-20231128.143052-42.jar` |
| Resolution | Direct | Via metadata |
| Version ordering | Normal | `1.0-SNAPSHOT` < `1.0` |

**maven-metadata.xml for SNAPSHOTs:**
Located at `groupId/artifactId/version-SNAPSHOT/maven-metadata.xml`:

```xml
<metadata>
  <groupId>org.example</groupId>
  <artifactId>my-lib</artifactId>
  <version>1.0-SNAPSHOT</version>
  <versioning>
    <snapshot>
      <timestamp>20231128.143052</timestamp>
      <buildNumber>42</buildNumber>
    </snapshot>
    <lastUpdated>20231128143052</lastUpdated>
    <snapshotVersions>
      <snapshotVersion>
        <extension>jar</extension>
        <value>1.0-20231128.143052-42</value>
        <updated>20231128143052</updated>
      </snapshotVersion>
      <snapshotVersion>
        <extension>pom</extension>
        <value>1.0-20231128.143052-42</value>
        <updated>20231128143052</updated>
      </snapshotVersion>
    </snapshotVersions>
  </versioning>
</metadata>
```

**Resolution algorithm:**
```dart
Future<String> resolveSnapshotVersion(
  ArtifactCoordinate coord,
  String packaging,
) async {
  if (!coord.version.endsWith('-SNAPSHOT')) {
    return coord.version;  // Not a snapshot
  }
  
  final metadataPath = '${coord.groupPath}/${coord.artifactId}/'
      '${coord.version}/maven-metadata.xml';
  
  final metadata = await fetchAndParseMetadata(metadataPath);
  
  // Find matching snapshotVersion entry
  final entry = metadata.snapshotVersions.firstWhere(
    (sv) => sv.extension == packaging && sv.classifier == coord.classifier,
    orElse: () {
      // Fallback: construct from timestamp/buildNumber
      final ts = metadata.snapshot.timestamp;
      final bn = metadata.snapshot.buildNumber;
      final base = coord.version.replaceFirst('-SNAPSHOT', '');
      return SnapshotVersion(value: '$base-$ts-$bn');
    },
  );
  
  return entry.value;  // e.g., "1.0-20231128.143052-42"
}
```

**Update policies:**

| Policy | Behavior |
|--------|----------|
| `always` | Check remote on every build |
| `daily` | Check once per 24 hours (default) |
| `interval:X` | Check every X minutes |
| `never` | Never check remote |

**For Rush CLI:**
- We should support SNAPSHOTs but can use simplified policy
- Default to `always` for extension development (users want latest)
- Store `lastUpdated` timestamp to avoid redundant fetches

**Filename resolution:**
```
Base: my-lib-1.0-SNAPSHOT.jar
Resolved: my-lib-1.0-20231128.143052-42.jar
```

---

## Addendum C: Updated Implementation Plan

### Phase 2 Additions

Add to repository layer:
- [ ] `maven_metadata.dart` - Metadata parsing model
- [ ] SNAPSHOT resolution support in `remote_repository.dart`
- [ ] Parallel fetch support with semaphore
- [ ] Configurable checksum policy

### Phase 3 Additions

Add to POM parsing:
- [ ] `relocation.dart` - Relocation model
- [ ] Relocation detection in POM parser
- [ ] 5-part coordinate parsing support

### Phase 4 Additions

Add to resolution:
- [ ] Relocation following with cycle detection
- [ ] SNAPSHOT timestamp resolution
- [ ] `system` scope handling in mediation

### New Files

```
lib/src/resolver/
├── coordinate.dart           # 5-part coordinate parsing
├── repository/
│   └── maven_metadata.dart   # Metadata parsing
├── pom/
│   └── relocation.dart       # Relocation model
└── snapshot/
    └── snapshot_resolver.dart # SNAPSHOT-specific logic
```

---

## Addendum D: Revised Effort Estimate

| Phase | Original | Revised | Delta | Reason |
|-------|----------|---------|-------|--------|
| Phase 1 | 2-3 days | 2-3 days | 0 | Unchanged |
| Phase 2 | 1-2 days | 2-3 days | +1 | Parallel fetches, SNAPSHOT metadata |
| Phase 3 | 2-3 days | 3-4 days | +1 | Relocation, 5-part coords |
| Phase 4 | 3-4 days | 4-5 days | +1 | Relocation following, system scope |
| Phase 5 | 1-2 days | 1-2 days | 0 | Unchanged |
| Phase 6 | 2-3 days | 2-3 days | 0 | Unchanged |
| **Total** | **11-17 days** | **14-20 days** | **+3** | |

The additional effort is worth it for full Maven compliance.

---

## Addendum E: Questions Resolved

| Question | Answer |
|----------|--------|
| Should resolver be reused? | No. Stateless design, per-call context. |
| Checksum failure behavior? | Configurable: fail/warn/ignore. Default: warn. |
| Parallel fetch limits? | Default 4 concurrent requests. Configurable. |
| SNAPSHOT update policy? | Support all. Default to `always` for Rush. |
| Relocation depth limit? | No explicit limit, but cycle detection prevents infinite loops. |
