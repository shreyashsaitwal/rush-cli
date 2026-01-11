/// Maven version parsing and comparison.
///
/// Implements Maven's ComparableVersion specification:
/// https://maven.apache.org/pom.html#Version_Order_Specification
///
/// Key features:
/// - Tokenization on `.`, `-`, `_`, and digit↔letter transitions
/// - Qualifier ordering: alpha < beta < milestone < rc < snapshot < "" < sp
/// - Trailing null trimming for normalization
/// - Case-insensitive comparison
library;

import 'version_item.dart';

/// A Maven version that can be compared according to Maven's ordering rules.
///
/// Maven versions are parsed into a hierarchical structure of items:
/// - Numeric segments become [IntItem]s
/// - Qualifier segments become [StringItem]s
/// - Hyphen and digit↔letter transitions create nested [ListItem]s
///
/// Example parsing:
/// ```
/// "1.0" → [1, 0]
/// "1.0-alpha-1" → [1, 0, [alpha, [1]]]
/// "1.0.1-2" → [1, 0, 1, [2]]
/// "1.0alpha1" → [1, 0, [alpha, [1]]]  (digit→letter transition)
/// ```
///
/// Versions are normalized by trimming trailing "null" values:
/// - `0` for integers
/// - `""`, `final`, `ga`, `release` for strings
/// - Empty lists
///
/// This means `1.0.0` equals `1`, and `1.ga` equals `1`.
final class MavenVersion implements Comparable<MavenVersion> {
  /// The original version string.
  final String original;

  /// The parsed items representing this version.
  final ListItem _items;

  /// The canonical string representation (normalized).
  late final String canonical;

  MavenVersion._(this.original, this._items) {
    canonical = _computeCanonical();
  }

  /// Parses a version string into a [MavenVersion].
  ///
  /// The version string is tokenized according to Maven rules:
  /// - `.` separates segments at the same level
  /// - `-` and `_` create a new nested level
  /// - Digit↔letter transitions create a new nested level
  ///
  /// Examples:
  /// ```dart
  /// MavenVersion.parse('1.0');        // 1.0
  /// MavenVersion.parse('1.0-alpha');  // 1-alpha
  /// MavenVersion.parse('1.0.FINAL');  // 1
  /// ```
  factory MavenVersion.parse(String version) {
    final items = _parse(version);
    return MavenVersion._(version, items);
  }

  /// Parses a version string into a normalized list of items.
  ///
  /// This follows Maven's ComparableVersion.parseVersion() algorithm exactly.
  static ListItem _parse(String version) {
    final versionLower = version.toLowerCase();
    final items = <VersionItem>[];
    var list = items;
    final stack = <List<VersionItem>>[list];

    var isDigit = false;
    var startIndex = 0;

    for (var i = 0; i < versionLower.length; i++) {
      final c = versionLower[i];

      if (c == '.') {
        if (i == startIndex) {
          list.add(IntItem.zero);
        } else {
          list.add(_parseItem(isDigit, versionLower.substring(startIndex, i)));
        }
        startIndex = i + 1;
      } else if (c == '-' || c == '_') {
        if (i == startIndex) {
          list.add(IntItem.zero);
        } else {
          list.add(_parseItem(isDigit, versionLower.substring(startIndex, i)));
        }
        startIndex = i + 1;

        // Create new nested list
        final newList = <VersionItem>[];
        list.add(ListItem(newList));
        list = newList;
        stack.add(list);
      } else if (_isDigit(c)) {
        if (!isDigit && i > startIndex) {
          // Transition from letter to digit
          // MNG-7644: treat .X as -X for any string qualifier X
          if (list.isNotEmpty) {
            final newList = <VersionItem>[];
            list.add(ListItem(newList));
            list = newList;
            stack.add(list);
          }

          list.add(
            StringItem.withFollowedByDigit(
              versionLower.substring(startIndex, i),
            ),
          );
          startIndex = i;

          // Create another nested list for the digit
          final newList = <VersionItem>[];
          list.add(ListItem(newList));
          list = newList;
          stack.add(list);
        }

        isDigit = true;
      } else {
        if (isDigit && i > startIndex) {
          // Transition from digit to letter
          list.add(_parseItem(true, versionLower.substring(startIndex, i)));
          startIndex = i;

          // Create new nested list
          final newList = <VersionItem>[];
          list.add(ListItem(newList));
          list = newList;
          stack.add(list);
        }

        isDigit = false;
      }
    }

    if (versionLower.length > startIndex) {
      // MNG-7644: treat .X as -X for any string qualifier X
      if (!isDigit && list.isNotEmpty) {
        final newList = <VersionItem>[];
        list.add(ListItem(newList));
        list = newList;
        stack.add(list);
      }

      list.add(_parseItem(isDigit, versionLower.substring(startIndex)));
    }

    // Normalize all lists in the stack (bottom-up)
    while (stack.isNotEmpty) {
      final listToNormalize = stack.removeLast();
      _normalizeList(listToNormalize);
    }

    return ListItem(items);
  }

  static bool _isDigit(String c) {
    final code = c.codeUnitAt(0);
    return code >= 48 && code <= 57; // '0' to '9'
  }

  static VersionItem _parseItem(bool isDigit, String buf) {
    if (isDigit) {
      final stripped = _stripLeadingZeroes(buf);
      return IntItem(BigInt.parse(stripped));
    }
    return StringItem(buf);
  }

  static String _stripLeadingZeroes(String buf) {
    if (buf.isEmpty) return '0';
    for (var i = 0; i < buf.length; i++) {
      if (buf[i] != '0') {
        return buf.substring(i);
      }
    }
    return '0';
  }

  /// Normalizes a list by trimming trailing null items.
  static void _normalizeList(List<VersionItem> list) {
    for (var i = list.length - 1; i >= 0; i--) {
      final item = list[i];
      if (item.isNull) {
        list.removeAt(i);
      } else if (item is! ListItem) {
        // Stop at first non-null, non-list item
        break;
      }
    }
  }

  /// Computes the canonical string representation.
  String _computeCanonical() {
    return _itemsToString(_items.items);
  }

  static String _itemsToString(List<VersionItem> items) {
    final buffer = StringBuffer();

    for (var i = 0; i < items.length; i++) {
      final item = items[i];

      if (i > 0) {
        buffer.write(item is ListItem ? '-' : '.');
      }

      switch (item) {
        case IntItem(:final value):
          buffer.write(value);
        case StringItem(:final qualifier):
          // Use normalized qualifier value for canonical form
          buffer.write(qualifier.value);
        case ListItem(:final items):
          buffer.write(_itemsToString(items));
      }
    }

    return buffer.toString();
  }

  @override
  int compareTo(MavenVersion other) {
    return _items.compareTo(other._items);
  }

  /// Returns true if this version is less than [other].
  bool operator <(MavenVersion other) => compareTo(other) < 0;

  /// Returns true if this version is less than or equal to [other].
  bool operator <=(MavenVersion other) => compareTo(other) <= 0;

  /// Returns true if this version is greater than [other].
  bool operator >(MavenVersion other) => compareTo(other) > 0;

  /// Returns true if this version is greater than or equal to [other].
  bool operator >=(MavenVersion other) => compareTo(other) >= 0;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MavenVersion && canonical == other.canonical;

  @override
  int get hashCode => canonical.hashCode;

  @override
  String toString() => original;
}
