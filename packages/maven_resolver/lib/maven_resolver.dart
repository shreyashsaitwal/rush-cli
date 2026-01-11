/// A Maven-compliant dependency resolver for Dart.
///
/// This library provides a complete implementation of Maven's version
/// comparison, dependency resolution, and POM parsing algorithms.
library;

// Version module
export 'src/version/maven_version.dart';
export 'src/version/version_range.dart';

// Repository module
export 'src/repository/artifact_coordinate.dart';
export 'src/repository/checksum.dart'
    show
        ChecksumAlgorithm,
        ChecksumResult,
        ChecksumValid,
        ChecksumInvalid,
        ChecksumMissing,
        ChecksumVerifier;
export 'src/repository/local_repository.dart';
export 'src/repository/maven_metadata.dart';
export 'src/repository/remote_repository.dart';
export 'src/repository/repository.dart';
export 'src/repository/repository_exception.dart';

// POM module
export 'src/pom/dependency.dart';
export 'src/pom/exclusion.dart';
export 'src/pom/pom.dart';
export 'src/pom/pom_interpolator.dart';
export 'src/pom/pom_parser.dart';

// Resolver module
export 'src/resolver/dependency_node.dart';
export 'src/resolver/effective_pom_builder.dart';
export 'src/resolver/resolution_context.dart';
export 'src/resolver/resolver.dart';
