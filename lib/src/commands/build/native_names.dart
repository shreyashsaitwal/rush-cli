import 'dart:convert';

const _jniPrefix = 'Java_';
const _minimumStringLength = 4;

final _className = RegExp(r'[A-Za-z_$][\w$]*(?:[/.][A-Za-z_$][\w$]*)+');
final _descriptor = RegExp(r'L([A-Za-z_$][\w$]*(?:/[A-Za-z_$][\w$]*)+);');
final _jniEscape = RegExp('/(?:0([0-9a-f]{4})|([123]))');

Set<String> namedClasses(List<int> library, Set<String> classes) => {
      for (final string in _strings(library))
        ...string.startsWith(_jniPrefix)
            ? _boundClass(string, classes)
            : _mentionedClasses(string, classes),
    };

Iterable<String> _strings(List<int> bytes) sync* {
  var start = 0;
  for (var i = 0; i <= bytes.length; i++) {
    if (i < bytes.length && bytes[i] >= 0x20 && bytes[i] < 0x7f) continue;
    if (i - start >= _minimumStringLength) {
      yield ascii.decode(bytes.sublist(start, i));
    }
    start = i + 1;
  }
}

Iterable<String> _boundClass(String symbol, Set<String> classes) sync* {
  final path =
      _demangled(symbol.substring(_jniPrefix.length).split('__').first);
  for (var end = path.lastIndexOf('/');
      end > 0;
      end = path.lastIndexOf('/', end - 1)) {
    final owner = path.substring(0, end);
    if (classes.contains(owner)) {
      yield owner;
      return;
    }
  }
}

String _demangled(String name) => name.replaceAll('_', '/').replaceAllMapped(
    _jniEscape,
    (match) => switch (match[2]) {
          null => String.fromCharCode(int.parse(match[1]!, radix: 16)),
          '1' => '_',
          '2' => ';',
          _ => '[',
        });

Iterable<String> _mentionedClasses(String string, Set<String> classes) => [
      for (final match in _descriptor.allMatches(string)) match[1]!,
      for (final match in _className.allMatches(string))
        match[0]!.replaceAll('.', '/'),
    ].where(classes.contains);
