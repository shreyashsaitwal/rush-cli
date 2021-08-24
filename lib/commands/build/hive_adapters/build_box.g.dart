// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'build_box.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class BuildBoxAdapter extends TypeAdapter<BuildBox> {
  @override
  final int typeId = 0;

  @override
  BuildBox read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return BuildBox(
      lastResolvedDeps: (fields[0] as List).cast<String>(),
      lastResolution: fields[1] as DateTime,
      kaptOpts: (fields[2] as Map).cast<String, String>(),
      previouslyLogged: (fields[3] as List).cast<String>(),
      lastManifMerge: fields[4] as DateTime,
    );
  }

  @override
  void write(BinaryWriter writer, BuildBox obj) {
    writer
      ..writeByte(5)
      ..writeByte(0)
      ..write(obj.lastResolvedDeps)
      ..writeByte(1)
      ..write(obj.lastResolution)
      ..writeByte(2)
      ..write(obj.kaptOpts)
      ..writeByte(3)
      ..write(obj.previouslyLogged)
      ..writeByte(4)
      ..write(obj.lastManifMerge);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BuildBoxAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
