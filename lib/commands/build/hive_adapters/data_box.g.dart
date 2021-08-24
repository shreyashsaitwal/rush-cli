// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'data_box.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class DataBoxAdapter extends TypeAdapter<DataBox> {
  @override
  final int typeId = 1;

  @override
  DataBox read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return DataBox(
      name: fields[0] as String,
      org: fields[1] as String,
      version: fields[2] as int,
    );
  }

  @override
  void write(BinaryWriter writer, DataBox obj) {
    writer
      ..writeByte(3)
      ..writeByte(0)
      ..write(obj.name)
      ..writeByte(1)
      ..write(obj.org)
      ..writeByte(2)
      ..write(obj.version);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DataBoxAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
