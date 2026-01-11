/// Qualifier handling for Maven version comparison.
///
/// Maven defines a specific ordering for version qualifiers:
/// ```
/// alpha < beta < milestone < rc=cr < snapshot < ""=final=ga=release < sp
/// ```
///
/// Unknown qualifiers come after all known qualifiers and are compared
/// case-insensitively as strings.
library;

/// Represents a version qualifier with its comparison value.
///
/// Qualifiers are ordered as:
/// - alpha (aliases: a) - lowest
/// - beta (aliases: b)
/// - milestone (aliases: m)
/// - rc (aliases: cr) - release candidate
/// - snapshot
/// - "" = final = ga = release - stable release
/// - sp - service pack (highest)
/// - unknown qualifiers - after sp, compared lexicographically
final class Qualifier implements Comparable<Qualifier> {
  /// The original string value (normalized to lowercase).
  final String value;

  /// The ordering value. Lower values sort first.
  /// Known qualifiers have values 0-6, unknown qualifiers use 7.
  final int order;

  const Qualifier._(this.value, this.order);

  /// Known qualifier ordering values.
  static const int _alphaOrder = 0;
  static const int _betaOrder = 1;
  static const int _milestoneOrder = 2;
  static const int _rcOrder = 3;
  static const int _snapshotOrder = 4;
  static const int _releaseOrder = 5; // "", final, ga, release
  static const int _spOrder = 6;
  static const int _unknownOrder = 7;

  /// Creates a Qualifier from a string value.
  ///
  /// Handles aliases and normalization:
  /// - "cr" → "rc"
  /// - "final", "ga", "release" → "" (empty/release)
  ///
  /// NOTE: Single-char aliases (a, b, m) are NOT expanded here.
  /// They are only expanded in StringItem.withFollowedByDigit when
  /// the qualifier is followed by a digit.
  factory Qualifier.fromString(String s) {
    final normalized = s.toLowerCase();

    return switch (normalized) {
      'alpha' => const Qualifier._('alpha', _alphaOrder),
      'beta' => const Qualifier._('beta', _betaOrder),
      'milestone' => const Qualifier._('milestone', _milestoneOrder),
      'rc' || 'cr' => const Qualifier._('rc', _rcOrder),
      'snapshot' => const Qualifier._('snapshot', _snapshotOrder),
      '' ||
      'final' ||
      'ga' ||
      'release' =>
        const Qualifier._('', _releaseOrder),
      'sp' => const Qualifier._('sp', _spOrder),
      _ => Qualifier._(normalized, _unknownOrder),
    };
  }

  /// Returns true if this qualifier represents a "null" value for normalization.
  ///
  /// Empty string, "final", "ga", and "release" are all null values.
  bool get isNull => order == _releaseOrder;

  /// Returns true if this is an unknown qualifier.
  bool get isUnknown => order == _unknownOrder;

  @override
  int compareTo(Qualifier other) {
    if (order != other.order) {
      return order.compareTo(other.order);
    }
    // Same order - for unknown qualifiers, compare lexicographically
    if (order == _unknownOrder) {
      return value.compareTo(other.value);
    }
    // Known qualifiers with same order are equal
    return 0;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Qualifier && order == other.order && value == other.value;

  @override
  int get hashCode => Object.hash(value, order);

  @override
  String toString() => value.isEmpty ? '(release)' : value;
}

/// Extension to check if a single character could be a qualifier alias.
///
/// Used during tokenization to determine if 'a', 'b', 'm' should be
/// expanded to their full qualifier names.
extension QualifierAlias on String {
  /// Returns true if this single character is a qualifier alias
  /// when followed by a digit (e.g., "1.0a1" → "1.0-alpha-1").
  bool get isQualifierAlias {
    if (length != 1) return false;
    final c = this[0].toLowerCase();
    return c == 'a' || c == 'b' || c == 'm';
  }

  /// Expands a single-character alias to its full qualifier name.
  String expandQualifierAlias() {
    if (length != 1) return this;
    return switch (this[0].toLowerCase()) {
      'a' => 'alpha',
      'b' => 'beta',
      'm' => 'milestone',
      _ => this,
    };
  }
}
