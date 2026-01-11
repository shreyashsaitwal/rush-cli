# Maven Resolver Implementation Plan - Finalized

**Approach**: Clean rewrite alongside existing code  
**Starting Point**: Phase 1 - Version Module  
**Test Strategy**: Port Maven's own test suite  
**Scope**: Full Maven compliance  

---

## Phase 1: Version Module (Days 1-3)

### Files to Create

```
lib/src/resolver/version/
├── maven_version.dart      # Main version class
├── version_range.dart      # Range parsing and matching
├── version_item.dart       # Item types (Int, String, List)
└── qualifier.dart          # Qualifier ordering logic

test/resolver/version/
├── maven_version_test.dart           # Ported from ComparableVersionTest.java
├── version_range_test.dart           # Ported from VersionRangeTest.java
└── version_comparison_test.dart      # Additional edge cases
```

### Implementation Order

1. **version_item.dart** - Base classes for version segments
   - `VersionItem` (sealed class)
   - `IntItem`, `LongItem`, `BigIntItem` for numbers
   - `StringItem` for qualifiers
   - `ListItem` for nested segments (after `-`)

2. **qualifier.dart** - Qualifier handling
   - Alias expansion (`a` → `alpha`, `cr` → `rc`, etc.)
   - Order values for known qualifiers
   - Comparison logic for unknown qualifiers

3. **maven_version.dart** - Main version class
   - Tokenization with proper separator handling
   - Normalization (trailing null removal)
   - Comparison (type priority + recursive)
   - Canonical string representation
   - `equals` based on canonical form

4. **version_range.dart** - Range support
   - Parse single ranges: `[1.0,2.0)`, `[1.0]`, etc.
   - Parse multi-ranges: `(,1.0],[1.2,)`
   - `contains(version)` method
   - `intersect(other)` method
   - `selectBest(available)` for picking optimal version
   - Soft vs hard requirement distinction

### Test Cases to Port

From Maven's `ComparableVersionTest.java`:
- `testVersionsQualifier()` - ~30 comparisons
- `testVersionsNumber()` - numeric comparisons
- `testVersionsEqual()` - equality cases
- `testVersionComparing()` - transitive comparison tests
- `testLocaleIndependent()` - case insensitivity

From Maven's `VersionRangeTest.java`:
- Range parsing tests
- Containment tests
- Intersection tests
- Invalid range handling

### Deliverables
- [ ] `MavenVersion` class with full spec compliance
- [ ] `VersionRange` class with all syntax support
- [ ] 100+ unit tests ported from Maven
- [ ] All tests passing

---

## Phase 2: Repository Layer (Days 4-5)

### Files to Create

```
lib/src/resolver/repository/
├── repository.dart           # Abstract interface
├── local_repository.dart     # .m2/repository access
├── remote_repository.dart    # HTTP with retry/timeout
└── checksum.dart             # Verification logic

test/resolver/repository/
├── local_repository_test.dart
├── remote_repository_test.dart
└── checksum_test.dart
```

### Implementation

1. **repository.dart** - Interface
   ```dart
   abstract class Repository {
     Future<File?> fetchPom(ArtifactCoordinate coord);
     Future<File?> fetchArtifact(ArtifactCoordinate coord, String packaging);
     Future<List<MavenVersion>> listVersions(String groupId, String artifactId);
   }
   ```

2. **local_repository.dart**
   - Read from `~/.m2/repository` or `M2_HOME`
   - Check file existence and non-zero size
   - Return cached files immediately

3. **remote_repository.dart**
   - Configurable timeout (default 30s)
   - Retry with exponential backoff (3 attempts)
   - Proper error propagation (never swallow!)
   - Connection pooling via http.Client
   - Support for repository authentication (future)

4. **checksum.dart**
   - Support sha1, md5, sha256, sha512
   - Handle missing checksum files gracefully
   - Clear error on verification failure

### Deliverables
- [ ] Repository abstraction with testable interface
- [ ] Local repository implementation
- [ ] Remote repository with retry/timeout
- [ ] Checksum verification
- [ ] Mock-based tests

---

## Phase 3: POM Parsing & Interpolation (Days 6-8)

### Files to Create

```
lib/src/resolver/pom/
├── pom.dart                  # Immutable POM model
├── pom_parser.dart           # XML → Pom
├── pom_interpolator.dart     # Property substitution
├── dependency.dart           # Dependency model
└── exclusion.dart            # Exclusion model

test/resolver/pom/
├── pom_parser_test.dart
├── pom_interpolator_test.dart
└── fixtures/                 # Real POM files for testing
    ├── simple.pom.xml
    ├── with_parent.pom.xml
    ├── with_bom.pom.xml
    └── spring_boot.pom.xml
```

### Implementation

1. **pom.dart** - Immutable model
   ```dart
   class Pom {
     final String groupId;
     final String artifactId;
     final String version;
     final String packaging;
     final Pom? parent;
     final Map<String, String> properties;
     final List<Dependency> dependencies;
     final List<Dependency> dependencyManagement;
   }
   ```

2. **pom_parser.dart**
   - Handle XML edge cases
   - Graceful handling of malformed POMs
   - Support both single `<dependency>` and list forms

3. **pom_interpolator.dart**
   - Property resolution order:
     1. Child POM properties (NOT parent first!)
     2. Parent POM properties (recursive)
     3. Project fields (`${project.version}`)
     4. Environment variables (`${env.X}`)
   - Handle circular references
   - Handle missing properties gracefully

4. **dependency.dart & exclusion.dart**
   - Full coordinate support (5 parts)
   - Scope with default `compile`
   - Optional flag
   - Exclusion list

### Key Fixes
- Property inheritance order (child overrides parent)
- BOM import without race conditions (sequential processing)
- Immutable POMs prevent concurrent modification

### Deliverables
- [ ] Immutable POM model
- [ ] Correct property interpolation
- [ ] Safe BOM import handling
- [ ] Tests with real-world POMs

---

## Phase 4: Resolution Algorithm (Days 9-12)

### Files to Create

```
lib/src/resolver/
├── resolver.dart             # Main entry point
├── resolution_context.dart   # Per-resolution state
├── dependency_tree.dart      # Tree structure
├── scope_mediator.dart       # Scope inheritance

lib/src/resolver/conflict/
├── conflict_resolver.dart    # Nearest wins + version selection
└── resolution_error.dart     # Error types

test/resolver/
├── resolver_test.dart
├── scope_mediator_test.dart
├── conflict_resolver_test.dart
└── fixtures/
    └── dependency_graphs/    # Test scenarios as JSON
```

### Implementation

1. **resolution_context.dart** - Per-call state
   ```dart
   class ResolutionContext {
     final Map<String, ResolvedArtifact> resolved;
     final Set<String> processing; // Cycle detection
     final Map<String, Pom> pomCache;
     final List<ResolutionPath> paths; // For "nearest wins"
   }
   ```

2. **resolver.dart** - Breadth-first resolution
   - Process dependencies level by level
   - Track depth for each artifact
   - Apply dependencyManagement at each level
   - Skip optional dependencies
   - Apply exclusions

3. **scope_mediator.dart** - Scope inheritance table
   - Implement the full mediation table
   - Handle scope demotion correctly

4. **conflict_resolver.dart** - Version selection
   - "Nearest wins" with depth tracking
   - First-declaration-wins for ties
   - dependencyManagement overrides mediation
   - Handle hard vs soft version requirements
   - Range intersection for multiple constraints

### Key Algorithms

**Breadth-First Resolution**:
```
queue = [direct dependencies at depth 1]
while queue not empty:
    dep = queue.pop()
    if already resolved at same or lower depth: skip
    resolve POM, interpolate
    apply dependencyManagement
    for each transitive dep:
        mediate scope
        if not excluded and not optional:
            queue.add(dep at depth+1)
```

**Conflict Resolution**:
```
for each artifact with multiple versions:
    if has version range constraints:
        intersect all ranges
        if no intersection: ERROR
        pick best from intersection
    else:
        pick version at minimum depth
        on tie: first declaration
    apply dependencyManagement version override
```

### Deliverables
- [ ] Stateless resolver with per-call context
- [ ] Correct breadth-first resolution
- [ ] Scope mediation
- [ ] Exclusion support
- [ ] Optional dependency filtering
- [ ] "Nearest wins" conflict resolution
- [ ] Version range constraint solving
- [ ] Comprehensive integration tests

---

## Phase 5: Conflict Resolution Deep Dive (Days 13-14)

### Additional Scenarios to Handle

1. **Range + Exact version conflicts**
   - Exact version wins if it satisfies range
   - Error if exact version outside range

2. **Multiple BOMs with same artifact**
   - First BOM declaration wins
   - Log warning for conflicts

3. **Diamond dependency with ranges**
   - A → B[1.0,2.0), C[1.5,3.0)
   - Intersection: [1.5,2.0)
   - Pick highest in intersection

4. **Unsatisfiable constraints**
   - Clear error message showing conflict path
   - Suggest resolution (exclude one path)

### Deliverables
- [ ] All edge case handling
- [ ] Clear error messages
- [ ] Debug logging for resolution decisions

---

## Phase 6: Integration & Migration (Days 15-17)

### Tasks

1. **Adapter layer**
   - Create `LegacyArtifact` ↔ `ResolvedArtifact` conversion
   - Create `Artifact` (Hive) ↔ `ResolvedArtifact` conversion

2. **Migrate sync.dart**
   - Replace `ArtifactResolver` usage with new resolver
   - Remove `_resolveVersionConflicts` (now built-in)
   - Update caching logic for new artifact model

3. **Migrate build.dart**
   - Update dependency retrieval
   - Update classpath construction

4. **Remove old implementation**
   - Delete old `resolver.dart`
   - Delete old `Version` class in `artifact.dart`
   - Update `artifact.dart` to use new `MavenVersion`

5. **End-to-end testing**
   - Test with known Rush projects
   - Test with projects that previously failed
   - Verify no regressions

### Deliverables
- [ ] All existing functionality preserved
- [ ] Old resolver code removed
- [ ] E2E tests passing
- [ ] Manual testing with real projects

---

## Test Matrix

| Test Type | Count | Location |
|-----------|-------|----------|
| Version comparison | ~100 | test/resolver/version/ |
| Version range | ~50 | test/resolver/version/ |
| Repository | ~20 | test/resolver/repository/ |
| POM parsing | ~30 | test/resolver/pom/ |
| Resolution | ~50 | test/resolver/ |
| Integration | ~20 | test/integration/ |
| **Total** | **~270** | |

---

## Success Criteria

1. **All Maven version comparison test cases pass**
2. **Zero race conditions** (no concurrent mutable state)
3. **Proper error propagation** (no swallowed exceptions)
4. **Timeout on all network operations**
5. **Retry with backoff on transient failures**
6. **Correct scope mediation** for transitive deps
7. **Working exclusions** for problematic transitives
8. **Full version range support** including multi-ranges
9. **Existing Rush projects build successfully**
10. **Previously failing projects now succeed** (if failure was resolver bug)

---

## Risks & Mitigations

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| Maven spec edge cases we didn't anticipate | Medium | Port Maven's actual tests |
| Breaking existing working projects | Low | Extensive E2E testing before migration |
| Performance regression (more correct = more work) | Medium | Add POM caching, parallelize where safe |
| Scope creep into other Rush issues | Medium | Stay focused on resolver only |

---

## Ready to Execute

When you give the go-ahead, I'll start with Phase 1:

1. Create the `version/` module structure
2. Implement `MavenVersion` following the spec
3. Port Maven's `ComparableVersionTest.java` test cases
4. Iterate until all tests pass

This foundation will make everything else much easier to build and verify.
