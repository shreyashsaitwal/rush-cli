# Maven Resolver Specification & Refactoring Plan

This document serves as a reference for the Rush CLI Maven resolver implementation.

---

## Part 1: Maven Version Comparison Specification

### 1.1 Tokenization Rules

Version strings are split into tokens using these rules:

1. **Explicit separators**: `.` (dot), `-` (hyphen), and `_` (underscore)
2. **Implicit separators**: Transitions between digits and letters
   - Example: `1.0alpha1` → `[1, 0, [alpha, 1]]`

### 1.2 Separator Semantics

| Separator | Effect |
|-----------|--------|
| `.` (dot) | Creates segment at same nesting level |
| `-` (hyphen) | Creates a new nested list (sub-version) |
| `_` (underscore) | Same as hyphen |
| digit↔letter | Same as hyphen (creates nested list) |

**Critical insight**: Hyphen creates a "sub-list" compared differently:
- `1.0.RC2 < 1.0-RC3 < 1.0.1`

### 1.3 Qualifier Ordering (Lowest to Highest)

```
alpha < beta < milestone < rc = cr < snapshot < "" = final = ga = release < sp
```

| Qualifier | Aliases | Notes |
|-----------|---------|-------|
| `alpha` | `a` (when followed by digit) | Lowest |
| `beta` | `b` (when followed by digit) | |
| `milestone` | `m` (when followed by digit) | |
| `rc` | `cr` | Release Candidate |
| `snapshot` | | Pre-release |
| `""` (empty) | `final`, `ga`, `release` | Stable release |
| `sp` | | Service Pack (highest) |

**Unknown qualifiers**: Come after all known qualifiers, compared case-insensitively.

### 1.4 Type Priority

When comparing different types:

| Comparison | Result |
|------------|--------|
| Number vs String | Number > String |
| Number vs List | Number > List |
| String vs List | String < List |

### 1.5 Version Normalization

Trailing "null" values are removed:
- Null values: `0`, `""`, `final`, `ga`, `release`
- `1.0.0` → `1`
- `1.ga` → `1`
- `1.0.0-foo.0.0` → `1-foo`

### 1.6 Comparison Examples

```
1 < 1.1
1-snapshot < 1 < 1-sp
1-foo2 < 1-foo10
1.foo < 1-1 < 1.1
1.ga = 1-ga = 1-0 = 1.0 = 1
1-a1 = 1-alpha-1
1.0-alpha1 = 1.0-ALPHA1  (case insensitive)
```

### 1.7 Version Range Syntax

| Syntax | Meaning |
|--------|---------|
| `1.0` | Soft requirement (can be overridden) |
| `[1.0]` | Exactly 1.0 |
| `(,1.0]` | x <= 1.0 |
| `[1.0,)` | x >= 1.0 |
| `[1.0,2.0]` | 1.0 <= x <= 2.0 |
| `[1.0,2.0)` | 1.0 <= x < 2.0 |
| `(,1.0],[1.2,)` | x <= 1.0 OR x >= 1.2 |

---

## Part 2: Dependency Resolution Algorithm

### 2.1 Scope Definitions

| Scope | Compile CP | Runtime CP | Test CP | Transitive? |
|-------|------------|------------|---------|-------------|
| compile | ✓ | ✓ | ✓ | Yes |
| provided | ✓ | ✗ | ✓ | No |
| runtime | ✗ | ✓ | ✓ | Yes |
| test | ✗ | ✗ | ✓ | No |
| system | ✓ | ✓ | ✓ | No |
| import | N/A | N/A | N/A | N/A (BOM only) |

### 2.2 Scope Mediation (Transitive Scope Inheritance)

| Direct Scope ↓ \ Transitive Scope → | compile | provided | runtime | test |
|-------------------------------------|---------|----------|---------|------|
| compile | compile | - | runtime | - |
| provided | provided | - | provided | - |
| runtime | runtime | - | runtime | - |
| test | test | - | test | - |

`-` means the dependency is **omitted** (not transitive).

### 2.3 "Nearest Wins" Conflict Resolution

1. Build complete dependency tree (breadth-first)
2. For conflicts, count depth from project root
3. **Shortest path wins**
4. On tie: **first declaration wins**

### 2.4 dependencyManagement

- Not automatically added to classpath
- Serves as version/config template
- **Takes precedence over "nearest wins"** for transitive deps
- Child POM overrides parent's dependencyManagement

### 2.5 BOM Imports

```xml
<dependency>
  <groupId>com.example</groupId>
  <artifactId>my-bom</artifactId>
  <version>1.0.0</version>
  <type>pom</type>
  <scope>import</scope>
</dependency>
```

- Imports are **replaced** with the BOM's dependencyManagement entries
- Process is recursive
- First declaration wins on conflicts
- Local declarations override imports

### 2.6 Property Interpolation

Sources (in resolution order):
1. `env.X` - Environment variables
2. `project.X` - POM elements (`${project.version}`)
3. `settings.X` - settings.xml values
4. Java System Properties
5. User-defined `<properties>`

**Inheritance**: Properties processed after inheritance; child values override parent.

### 2.7 Exclusions

- Applied per-dependency
- Excludes from **entire subtree** below that dependency
- Only groupId:artifactId (no version)
- Wildcard: `<groupId>*</groupId><artifactId>*</artifactId>`

### 2.8 Optional Dependencies

- `<optional>true</optional>`
- Included for declaring project
- **NOT included transitively** by default
- Consumers must explicitly declare if needed

---

## Part 3: Current Implementation Bugs

### Critical Bugs

| # | Bug | Location | Impact |
|---|-----|----------|--------|
| 1 | Swallowed exception in `_fetchFile` | resolver.dart:129-131 | Silent network failures |
| 2 | Substring without bounds check | resolver.dart:368-370 | Crash on normal groupIds |
| 3 | Race condition in BOM imports | resolver.dart:279-287 | Concurrent Set mutation |
| 4 | Property inheritance reversed | resolver.dart:235-238 | Parent overrides child |
| 5 | `_alreadyResolved` never cleared | resolver.dart:292 | Stale state across calls |

### Logical Bugs

| # | Bug | Location | Impact |
|---|-----|----------|--------|
| 6 | Version range picks boundary, not best | resolver.dart:173-181 | Fails if boundary doesn't exist |
| 7 | BOM artifactId matching too loose | resolver.dart:203-204 | Missing BOM versions |
| 8 | Coordinate parsing only handles 3-4 parts | resolver.dart:22-24 | Fails with packaging in coord |
| 9 | No scope mediation for transitives | resolver.dart:353-361 | Wrong scope propagation |

### Version Comparison Bugs

| # | Bug | Location | Impact |
|---|-----|----------|--------|
| 10 | Only splits on `.`, not `-` | artifact.dart:143 | `1.0-beta` parsed wrong |
| 11 | No qualifier ordering | artifact.dart:151-158 | alpha/beta/rc wrong order |
| 12 | No version normalization | artifact.dart | `1.0.0` != `1` |
| 13 | Range regex incomplete | artifact.dart:161-162 | Spaces, multi-range fail |

### Missing Features

| # | Feature | Impact |
|---|---------|--------|
| 14 | No exclusion support | Can't exclude bad transitives |
| 15 | No HTTP timeout | Hangs on unresponsive repos |
| 16 | No retry logic | Transient failures crash build |
| 17 | No POM caching | Re-parses same POMs repeatedly |

---

## Part 4: Refactored Architecture

### 4.1 New File Structure

```
lib/src/resolver/
├── resolver.dart           # Main ArtifactResolver class (orchestration only)
├── version/
│   ├── version.dart        # MavenVersion class (comparison logic)
│   ├── version_range.dart  # VersionRange class (range parsing/matching)
│   └── version_item.dart   # Internal: IntItem, StringItem, ListItem
├── pom/
│   ├── pom.dart            # Pom class (model)
│   ├── pom_parser.dart     # XML parsing logic
│   └── pom_interpolator.dart # Property interpolation
├── artifact.dart           # Artifact model (no version logic)
├── scope.dart              # Scope enum and mediation logic
├── repository/
│   ├── repository.dart     # Abstract repository interface
│   ├── remote_repository.dart # HTTP-based repo
│   └── local_repository.dart  # Local .m2 cache
├── conflict/
│   └── conflict_resolver.dart # "Nearest wins" + range resolution
└── cache/
    └── resolution_cache.dart  # In-memory POM/artifact cache
```

### 4.2 Key Design Decisions

1. **Stateless resolver**: No instance state that persists across calls. Each `resolve()` creates fresh context.

2. **Separate version module**: `MavenVersion` is a self-contained, well-tested class implementing the full spec.

3. **Repository abstraction**: Makes testing easy (mock repositories), supports future extensions.

4. **Explicit cache management**: Cache is passed in or created per-resolution, never leaked.

5. **Scope mediation built-in**: Scope is mediated during tree construction, not after.

### 4.3 Core Classes

#### MavenVersion
```dart
class MavenVersion implements Comparable<MavenVersion> {
  factory MavenVersion.parse(String version);
  
  bool satisfies(VersionRange range);
  String get canonical; // Normalized form
  
  @override
  int compareTo(MavenVersion other);
  
  @override
  bool operator ==(Object other); // Based on canonical
}
```

#### VersionRange
```dart
class VersionRange {
  factory VersionRange.parse(String spec);
  
  bool contains(MavenVersion version);
  VersionRange? intersect(VersionRange other);
  bool get isSoft; // e.g., "1.0" vs "[1.0]"
  
  // For selecting best version from available list
  MavenVersion? selectBest(List<MavenVersion> available);
}
```

#### ArtifactResolver
```dart
class ArtifactResolver {
  final List<Repository> repositories;
  final Duration timeout;
  final int maxRetries;
  
  Future<ResolutionResult> resolve(
    List<DependencySpec> dependencies, {
    Set<String> excludes = const {},
  });
}

class ResolutionResult {
  final List<ResolvedArtifact> artifacts;
  final List<ResolutionConflict> conflicts; // For reporting
  final DependencyTree tree; // For visualization
}
```

---

## Part 5: Implementation Plan

### Phase 1: Version Module (Foundation)
**Goal**: Correct, spec-compliant version comparison

1. Implement `MavenVersion` with proper tokenization
2. Implement qualifier ordering
3. Implement normalization
4. Implement `VersionRange` with full syntax support
5. **Write exhaustive tests** using Maven's own test cases

**Test cases to port from Maven**:
- ComparableVersionTest.java
- VersionRangeTest.java

### Phase 2: Repository Layer
**Goal**: Reliable, testable artifact fetching

1. Create `Repository` interface
2. Implement `LocalRepository` (read from .m2)
3. Implement `RemoteRepository` with:
   - Configurable timeout
   - Retry with exponential backoff
   - Proper error propagation
4. Implement checksum verification
5. **Write tests with mock HTTP**

### Phase 3: POM Parsing & Interpolation
**Goal**: Correct POM interpretation

1. Refactor `Pom` to be immutable
2. Implement `PomInterpolator` with correct inheritance order
3. Handle all property sources
4. Handle BOM imports without race conditions
5. **Write tests with real-world POMs**

### Phase 4: Resolution Algorithm
**Goal**: Correct dependency tree construction

1. Implement breadth-first resolution
2. Implement scope mediation
3. Implement "nearest wins" with depth tracking
4. Implement dependencyManagement override
5. Implement exclusions
6. Implement optional dependency filtering
7. **Write integration tests**

### Phase 5: Conflict Resolution
**Goal**: Correct version selection

1. Implement hard vs soft requirement handling
2. Implement range intersection
3. Implement "pick best from available" for ranges
4. Clear error messages for unsatisfiable constraints
5. **Write conflict scenario tests**

### Phase 6: Integration & Migration
**Goal**: Drop-in replacement

1. Create adapter layer for existing code
2. Migrate `sync.dart` to use new resolver
3. Migrate `build.dart` to use new resolver
4. Remove old implementation
5. **End-to-end tests with real projects**

---

## Part 6: Test Strategy

### Unit Tests

| Component | Test Focus |
|-----------|------------|
| MavenVersion | Parsing, comparison, normalization, equality |
| VersionRange | Parsing, contains, intersection, edge cases |
| PomParser | XML edge cases, malformed POMs |
| PomInterpolator | Property resolution, inheritance |
| ScopeMediator | All scope combinations |

### Integration Tests

| Scenario | Description |
|----------|-------------|
| Simple tree | A → B → C, no conflicts |
| Diamond | A → B,C; B,C → D (different versions) |
| Deep tree | 10+ levels deep |
| BOM import | Spring Boot style BOM |
| Exclusions | Exclude transitive dep |
| Ranges | Version range resolution |
| Mixed scopes | compile/runtime/provided mix |

### Real-World Tests

| Project | Why |
|---------|-----|
| OkHttp | Popular, deep tree |
| Gson | Simple, stable |
| Spring Boot Starter | BOM-heavy, complex |
| Kotlin stdlib | Known to cause issues |

### Property-Based Tests

- Generate random version strings, verify comparison is transitive
- Generate random POMs, verify interpolation is idempotent
- Generate random dependency graphs, verify resolution terminates

---

## Part 7: Answers to Your Questions

### Should resolver instance be reused?

**No.** Each resolution should have isolated state. The `_alreadyResolved` leak is a bug. 

New design: `ArtifactResolver` is stateless. Each `resolve()` call creates an internal `ResolutionContext` that holds all per-resolution state.

### What about backward compatibility?

Per your direction, correctness over compatibility. However, we should:
1. Log when the new resolver picks a different version than old would have
2. Provide a `--verbose` flag showing resolution decisions
3. Document breaking changes in release notes

---

## Part 8: Estimated Effort

| Phase | Effort | Complexity |
|-------|--------|------------|
| Phase 1: Version | 2-3 days | High (spec is subtle) |
| Phase 2: Repository | 1-2 days | Medium |
| Phase 3: POM | 2-3 days | High |
| Phase 4: Resolution | 3-4 days | High |
| Phase 5: Conflicts | 1-2 days | Medium |
| Phase 6: Integration | 2-3 days | Medium |
| **Total** | **11-17 days** | |

This assumes focused effort with good test coverage at each phase.

---

## Appendix: Reference Materials

- [Maven Version Order Specification](https://maven.apache.org/pom.html#Version_Order_Specification)
- [Maven ComparableVersion.java](https://github.com/apache/maven/blob/master/maven-artifact/src/main/java/org/apache/maven/artifact/versioning/ComparableVersion.java)
- [Maven Dependency Mechanism](https://maven.apache.org/guides/introduction/introduction-to-dependency-mechanism.html)
- [Maven POM Reference](https://maven.apache.org/pom.html)
