/// Maven version range parsing and matching.
///
/// Supports the full Maven version range syntax:
/// - `1.0` - Soft requirement (recommendation)
/// - `[1.0]` - Exactly 1.0
/// - `(,1.0]` - x <= 1.0
/// - `[1.0,)` - x >= 1.0
/// - `[1.0,2.0]` - 1.0 <= x <= 2.0
/// - `[1.0,2.0)` - 1.0 <= x < 2.0
/// - `(,1.0],[1.2,)` - x <= 1.0 OR x >= 1.2 (multi-range)
library;

import 'maven_version.dart';

/// Represents a Maven version range or version requirement.
///
/// A range can be:
/// - A soft requirement: just a version like "1.0" (can be overridden)
/// - A hard requirement: bracketed range like "[1.0,2.0)"
/// - A multi-range: comma-separated ranges like "(,1.0],[1.2,)"
///
/// Example usage:
/// ```dart
/// final range = VersionRange.parse('[1.0,2.0)');
/// print(range.contains(MavenVersion.parse('1.5'))); // true
/// print(range.contains(MavenVersion.parse('2.0'))); // false
/// ```
sealed class VersionRange {
  const VersionRange();

  /// Parses a version range specification.
  ///
  /// Supports:
  /// - Soft requirements: `1.0`
  /// - Exact versions: `[1.0]`
  /// - Ranges: `[1.0,2.0)`, `(1.0,2.0]`, etc.
  /// - Multi-ranges: `(,1.0],[1.2,)`
  factory VersionRange.parse(String spec) {
    final trimmed = spec.trim();
    if (trimmed.isEmpty) {
      throw FormatException('Empty version range: "$spec"');
    }

    // Check if this looks like a range (starts with [ or ()
    if (!trimmed.startsWith('[') && !trimmed.startsWith('(')) {
      // Soft requirement - just a version
      return SoftRequirement(MavenVersion.parse(trimmed));
    }

    // Parse as range(s)
    final ranges = <_Restriction>[];
    var remaining = trimmed;

    while (remaining.isNotEmpty) {
      // Find the end of this range
      final closeBracket = remaining.indexOf(']');
      final closeParen = remaining.indexOf(')');

      int endIndex;
      if (closeBracket == -1 && closeParen == -1) {
        throw FormatException('Unclosed range in: "$spec"');
      } else if (closeBracket == -1) {
        endIndex = closeParen;
      } else if (closeParen == -1) {
        endIndex = closeBracket;
      } else {
        endIndex = closeBracket < closeParen ? closeBracket : closeParen;
      }

      final rangeStr = remaining.substring(0, endIndex + 1);
      ranges.add(_parseRestriction(rangeStr, spec));

      remaining = remaining.substring(endIndex + 1);
      if (remaining.startsWith(',')) {
        remaining = remaining.substring(1);
      }
    }

    if (ranges.isEmpty) {
      throw FormatException('No valid ranges found in: "$spec"');
    }

    if (ranges.length == 1) {
      return HardRequirement._(ranges.first);
    }

    return MultiRange._(ranges);
  }

  /// Parses a single restriction like "[1.0,2.0)" or "[1.0]".
  static _Restriction _parseRestriction(String rangeStr, String original) {
    final lowerInclusive = rangeStr.startsWith('[');
    final upperInclusive = rangeStr.endsWith(']');

    // Remove brackets
    final inner = rangeStr.substring(1, rangeStr.length - 1);

    // Check for exact version [1.0]
    if (!inner.contains(',')) {
      if (!lowerInclusive || !upperInclusive) {
        throw FormatException(
          'Exact version must use [] brackets: "$rangeStr" in "$original"',
        );
      }
      final version = MavenVersion.parse(inner);
      return _Restriction(version, true, version, true);
    }

    // Parse range with comma
    final commaIndex = inner.indexOf(',');
    final lowerStr = inner.substring(0, commaIndex).trim();
    final upperStr = inner.substring(commaIndex + 1).trim();

    final lowerBound = lowerStr.isEmpty ? null : MavenVersion.parse(lowerStr);
    final upperBound = upperStr.isEmpty ? null : MavenVersion.parse(upperStr);

    // Validate bounds
    if (lowerBound != null && upperBound != null) {
      if (lowerBound > upperBound) {
        throw FormatException(
          'Lower bound exceeds upper bound: "$rangeStr" in "$original"',
        );
      }
    }

    return _Restriction(
      lowerBound,
      lowerInclusive,
      upperBound,
      upperInclusive,
    );
  }

  /// Returns true if [version] satisfies this range.
  bool contains(MavenVersion version);

  /// Returns true if this is a soft requirement (can be overridden).
  bool get isSoft;

  /// Returns true if this is a hard requirement (must be satisfied).
  bool get isHard => !isSoft;

  /// Attempts to intersect this range with another.
  ///
  /// Returns null if the ranges don't overlap.
  VersionRange? intersect(VersionRange other);

  /// Selects the best (highest) version from [available] that satisfies this range.
  ///
  /// Returns null if no version satisfies the range.
  MavenVersion? selectBest(List<MavenVersion> available) {
    MavenVersion? best;
    for (final version in available) {
      if (contains(version)) {
        if (best == null || version > best) {
          best = version;
        }
      }
    }
    return best;
  }
}

/// A soft version requirement (can be overridden by other declarations).
///
/// This is what you get when you declare a dependency without brackets:
/// ```xml
/// <version>1.0</version>
/// ```
final class SoftRequirement extends VersionRange {
  /// The recommended version.
  final MavenVersion version;

  const SoftRequirement(this.version);

  @override
  bool get isSoft => true;

  @override
  bool contains(MavenVersion version) {
    // Soft requirements match any version >= the recommended version
    // In practice, Maven treats soft requirements as "prefer this version"
    // but they can be overridden. For `contains`, we check exact match.
    return version == this.version;
  }

  @override
  VersionRange? intersect(VersionRange other) {
    // Soft requirements defer to hard requirements
    if (other is HardRequirement || other is MultiRange) {
      if (other.contains(version)) {
        return this;
      }
      return other;
    }
    if (other is SoftRequirement) {
      // Take the higher version
      return version >= other.version ? this : other;
    }
    return null;
  }

  @override
  String toString() => version.toString();
}

/// A hard version requirement that must be satisfied.
///
/// This is what you get when you declare a dependency with brackets:
/// ```xml
/// <version>[1.0,2.0)</version>
/// ```
final class HardRequirement extends VersionRange {
  final _Restriction _restriction;

  const HardRequirement._(this._restriction);

  /// Creates an exact version requirement.
  factory HardRequirement.exact(MavenVersion version) {
    return HardRequirement._(_Restriction(version, true, version, true));
  }

  /// Creates a minimum version requirement (>= version).
  factory HardRequirement.atLeast(MavenVersion version) {
    return HardRequirement._(_Restriction(version, true, null, false));
  }

  /// Creates a maximum version requirement (<= version).
  factory HardRequirement.atMost(MavenVersion version) {
    return HardRequirement._(_Restriction(null, false, version, true));
  }

  @override
  bool get isSoft => false;

  @override
  bool contains(MavenVersion version) => _restriction.contains(version);

  @override
  VersionRange? intersect(VersionRange other) {
    switch (other) {
      case SoftRequirement(:final version):
        // If soft requirement's version is in our range, keep it
        if (contains(version)) {
          return other;
        }
        // Otherwise, just return ourselves (hard beats soft)
        return this;

      case HardRequirement(:final _restriction):
        final intersection = this._restriction.intersect(_restriction);
        if (intersection == null) return null;
        return HardRequirement._(intersection);

      case MultiRange():
        return other.intersect(this);
    }
  }

  @override
  String toString() => _restriction.toString();
}

/// A multi-range requirement (union of multiple ranges).
///
/// Example: `(,1.0],[1.2,)` means "x <= 1.0 OR x >= 1.2"
final class MultiRange extends VersionRange {
  final List<_Restriction> _restrictions;

  const MultiRange._(this._restrictions);

  @override
  bool get isSoft => false;

  @override
  bool contains(MavenVersion version) {
    return _restrictions.any((r) => r.contains(version));
  }

  @override
  VersionRange? intersect(VersionRange other) {
    switch (other) {
      case SoftRequirement(:final version):
        if (contains(version)) {
          return other;
        }
        return this;

      case HardRequirement(:final _restriction):
        final intersections = <_Restriction>[];
        for (final r in _restrictions) {
          final intersection = r.intersect(_restriction);
          if (intersection != null) {
            intersections.add(intersection);
          }
        }
        if (intersections.isEmpty) return null;
        if (intersections.length == 1) {
          return HardRequirement._(intersections.first);
        }
        return MultiRange._(intersections);

      case MultiRange(:final _restrictions):
        final intersections = <_Restriction>[];
        for (final r1 in this._restrictions) {
          for (final r2 in _restrictions) {
            final intersection = r1.intersect(r2);
            if (intersection != null) {
              intersections.add(intersection);
            }
          }
        }
        if (intersections.isEmpty) return null;
        if (intersections.length == 1) {
          return HardRequirement._(intersections.first);
        }
        return MultiRange._(intersections);
    }
  }

  @override
  String toString() => _restrictions.join(',');
}

/// Internal class representing a single version restriction.
///
/// A restriction has optional lower and upper bounds, each of which
/// can be inclusive or exclusive.
final class _Restriction {
  final MavenVersion? lowerBound;
  final bool lowerInclusive;
  final MavenVersion? upperBound;
  final bool upperInclusive;

  const _Restriction(
    this.lowerBound,
    this.lowerInclusive,
    this.upperBound,
    this.upperInclusive,
  );

  /// Returns true if [version] is within this restriction.
  bool contains(MavenVersion version) {
    // Check lower bound
    if (lowerBound != null) {
      final cmp = version.compareTo(lowerBound!);
      if (cmp < 0) return false;
      if (cmp == 0 && !lowerInclusive) return false;
    }

    // Check upper bound
    if (upperBound != null) {
      final cmp = version.compareTo(upperBound!);
      if (cmp > 0) return false;
      if (cmp == 0 && !upperInclusive) return false;
    }

    return true;
  }

  /// Intersects this restriction with another.
  ///
  /// Returns null if the restrictions don't overlap.
  _Restriction? intersect(_Restriction other) {
    // Compute new lower bound (take the higher one)
    MavenVersion? newLower;
    bool newLowerInclusive;

    if (lowerBound == null) {
      newLower = other.lowerBound;
      newLowerInclusive = other.lowerInclusive;
    } else if (other.lowerBound == null) {
      newLower = lowerBound;
      newLowerInclusive = lowerInclusive;
    } else {
      final cmp = lowerBound!.compareTo(other.lowerBound!);
      if (cmp > 0) {
        newLower = lowerBound;
        newLowerInclusive = lowerInclusive;
      } else if (cmp < 0) {
        newLower = other.lowerBound;
        newLowerInclusive = other.lowerInclusive;
      } else {
        newLower = lowerBound;
        // Both inclusive only if both are inclusive
        newLowerInclusive = lowerInclusive && other.lowerInclusive;
      }
    }

    // Compute new upper bound (take the lower one)
    MavenVersion? newUpper;
    bool newUpperInclusive;

    if (upperBound == null) {
      newUpper = other.upperBound;
      newUpperInclusive = other.upperInclusive;
    } else if (other.upperBound == null) {
      newUpper = upperBound;
      newUpperInclusive = upperInclusive;
    } else {
      final cmp = upperBound!.compareTo(other.upperBound!);
      if (cmp < 0) {
        newUpper = upperBound;
        newUpperInclusive = upperInclusive;
      } else if (cmp > 0) {
        newUpper = other.upperBound;
        newUpperInclusive = other.upperInclusive;
      } else {
        newUpper = upperBound;
        // Both inclusive only if both are inclusive
        newUpperInclusive = upperInclusive && other.upperInclusive;
      }
    }

    // Check if the intersection is valid (lower <= upper)
    if (newLower != null && newUpper != null) {
      final cmp = newLower.compareTo(newUpper);
      if (cmp > 0) return null; // No overlap
      if (cmp == 0 && (!newLowerInclusive || !newUpperInclusive)) {
        return null; // No overlap (exclusive bounds that meet)
      }
    }

    return _Restriction(
      newLower,
      newLowerInclusive,
      newUpper,
      newUpperInclusive,
    );
  }

  @override
  String toString() {
    final buffer = StringBuffer();

    buffer.write(lowerInclusive ? '[' : '(');

    if (lowerBound != null && upperBound != null && lowerBound == upperBound) {
      // Exact version
      buffer.write(lowerBound);
    } else {
      buffer.write(lowerBound?.toString() ?? '');
      buffer.write(',');
      buffer.write(upperBound?.toString() ?? '');
    }

    buffer.write(upperInclusive ? ']' : ')');

    return buffer.toString();
  }
}
