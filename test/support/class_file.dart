import 'dart:convert';
import 'dart:typed_data';

Set<String> fieldNames(List<int> classFile) => _memberNames(classFile).fields;

Set<String> methodNames(List<int> classFile) => _memberNames(classFile).methods;

({Set<String> fields, Set<String> methods}) _memberNames(List<int> classFile) {
  final reader = _Reader(Uint8List.fromList(classFile))..skip(8);
  final names = _constantPoolNames(reader);
  reader.skip(6);
  reader.skip(2 * reader.u2());
  final fields = {
    for (var fields = reader.u2(); fields > 0; fields--)
      names[_skipMember(reader)]!,
  };
  final methods = {
    for (var methods = reader.u2(); methods > 0; methods--)
      names[_skipMember(reader)]!,
  };
  return (fields: fields, methods: methods);
}

Map<int, String> _constantPoolNames(_Reader reader) {
  final names = <int, String>{};
  final count = reader.u2();
  for (var index = 1; index < count; index++) {
    switch (reader.u1()) {
      case 1:
        names[index] =
            utf8.decode(reader.bytes(reader.u2()), allowMalformed: true);
      case 3 || 4 || 9 || 10 || 11 || 12 || 17 || 18:
        reader.skip(4);
      case 5 || 6:
        reader.skip(8);
        index++;
      case 7 || 8 || 16 || 19 || 20:
        reader.skip(2);
      case 15:
        reader.skip(3);
      case final tag:
        throw FormatException('Unknown constant pool tag $tag');
    }
  }
  return names;
}

int _skipMember(_Reader reader) {
  reader.skip(2);
  final name = reader.u2();
  reader.skip(2);
  for (var attributes = reader.u2(); attributes > 0; attributes--) {
    reader
      ..skip(2)
      ..skip(reader.u4());
  }
  return name;
}

class _Reader {
  _Reader(this._data) : _view = ByteData.sublistView(_data);

  final Uint8List _data;
  final ByteData _view;
  var _offset = 0;

  void skip(int count) => _offset += count;

  int u1() => _view.getUint8(_offset++);

  int u2() {
    final value = _view.getUint16(_offset);
    _offset += 2;
    return value;
  }

  int u4() {
    final value = _view.getUint32(_offset);
    _offset += 4;
    return value;
  }

  Uint8List bytes(int count) {
    final value = Uint8List.sublistView(_data, _offset, _offset + count);
    _offset += count;
    return value;
  }
}
