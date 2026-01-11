/// Version item types used in Maven version comparison.
///
/// Maven versions are parsed into a tree of items:
/// - [IntItem] for numeric segments
/// - [StringItem] for qualifier segments (alpha, beta, rc, etc.)
/// - [ListItem] for nested segments (created by `-` separator)
///
/// The comparison rules follow Maven's ComparableVersion specification.
library;

import 'qualifier.dart';

/// Base class for all version item types.
///
/// Items are compared according to Maven rules:
/// - Numbers > Lists > Strings (when types differ)
/// - Same types compared by value
sealed class VersionItem implements Comparable<VersionItem> {
  const VersionItem();

  /// Returns true if this item represents a "null" value for normalization.
  ///
  /// Null values are trimmed from the end of version lists:
  /// - 0 for integers
  /// - "" (empty), "final", "ga", "release" for strings
  /// - Empty list for lists
  bool get isNull;

  /// Compare this item to another item.
  ///
  /// When comparing different types:
  /// - Numbers > Lists > Strings
  @override
  int compareTo(VersionItem other);
}

/// Integer version segment (e.g., "1", "23", "456").
///
/// Uses BigInt internally to handle arbitrarily large version numbers.
final class IntItem extends VersionItem {
  final BigInt value;

  const IntItem(this.value);

  /// The zero value, used for null comparisons.
  static final BigInt _zero = BigInt.zero;

  /// A reusable zero IntItem for null comparisons.
  static final IntItem zero = IntItem(_zero);

  factory IntItem.parse(String s) => IntItem(BigInt.parse(s));

  @override
  bool get isNull => value == _zero;

  @override
  int compareTo(VersionItem other) {
    return switch (other) {
      IntItem(:final value) => this.value.compareTo(value),
      StringItem() => 1, // Number > String
      ListItem() => 1, // Number > List
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is IntItem && value == other.value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value.toString();
}

/// String version segment (qualifiers like "alpha", "beta", "SNAPSHOT").
///
/// Qualifiers have a defined ordering:
/// alpha < beta < milestone < rc=cr < snapshot < ""=final=ga=release < sp
///
/// Unknown qualifiers come after all known qualifiers and are compared
/// case-insensitively.
final class StringItem extends VersionItem {
  final String value;

  /// The comparable qualifier value (normalized, lowercase).
  final Qualifier qualifier;

  StringItem(String value)
      : value = value,
        qualifier = Qualifier.fromString(value);

  /// Creates a StringItem with alias expansion for single-char qualifiers
  /// when followed by a digit (a → alpha, b → beta, m → milestone).
  factory StringItem.withFollowedByDigit(String value) {
    if (value.length == 1) {
      final expanded = switch (value) {
        'a' => 'alpha',
        'b' => 'beta',
        'm' => 'milestone',
        _ => value,
      };
      return StringItem(expanded);
    }
    return StringItem(value);
  }

  @override
  bool get isNull => qualifier.isNull;

  @override
  int compareTo(VersionItem other) {
    return switch (other) {
      IntItem() => -1, // String < Number
      StringItem(:final qualifier) => this.qualifier.compareTo(qualifier),
      ListItem(:final items) =>
        // String < List if list is not empty, String > empty List
        items.isEmpty ? 1 : -1,
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StringItem && qualifier == other.qualifier;

  @override
  int get hashCode => qualifier.hashCode;

  @override
  String toString() => value;
}

/// List of version items (created by `-` separator in version string).
///
/// Examples:
/// - `1.0-alpha` → ListItem([IntItem(1)], [ListItem([StringItem(alpha)])])
/// - `1.0.1-2` → ListItem([1, 0, 1], [ListItem([2])])
final class ListItem extends VersionItem {
  final List<VersionItem> items;

  const ListItem(this.items);

  /// Creates an empty list item.
  const ListItem.empty() : items = const [];

  @override
  bool get isNull => items.isEmpty;

  @override
  int compareTo(VersionItem other) {
    return switch (other) {
      IntItem() => -1, // List < Number
      StringItem(:final qualifier) =>
        // Empty list < String, non-empty list > String
        items.isEmpty ? (qualifier.isNull ? 0 : -1) : 1,
      ListItem(:final items) => _compareItems(items),
    };
  }

  int _compareItems(List<VersionItem> otherItems) {
    final thisIter = items.iterator;
    final otherIter = otherItems.iterator;

    while (true) {
      final thisHasNext = thisIter.moveNext();
      final otherHasNext = otherIter.moveNext();

      if (!thisHasNext && !otherHasNext) {
        return 0; // Both exhausted, equal
      }

      // Treat missing items as null
      final thisItem =
          thisHasNext ? thisIter.current : _nullFor(otherIter.current);
      final otherItem =
          otherHasNext ? otherIter.current : _nullFor(thisIter.current);

      final result = thisItem.compareTo(otherItem);
      if (result != 0) {
        return result;
      }
    }
  }

  /// Returns the "null" value for comparing against the given item type.
  static VersionItem _nullFor(VersionItem item) {
    return switch (item) {
      IntItem() => IntItem.zero,
      StringItem() => StringItem(''),
      ListItem() => const ListItem.empty(),
    };
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! ListItem) return false;
    if (items.length != other.items.length) return false;
    for (var i = 0; i < items.length; i++) {
      if (items[i] != other.items[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(items);

  @override
  String toString() => items.join('.');
}
