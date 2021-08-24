import 'package:hive/hive.dart';

part 'data_box.g.dart';

@HiveType(typeId: 1)
class DataBox extends HiveObject {
  @HiveField(0)
  final String name;

  @HiveField(1)
  final String org;

  @HiveField(2)
  final int version;

  DataBox({required this.name, required this.org, required this.version});
}

extension DataBoxExtensions on Box<DataBox> {
  void updateName(String newVal) {
    final old = getAt(0);
    putAt(
        0,
        DataBox(
          name: newVal,
          org: old!.org,
          version: old.version,
        ));
  }

  void updateOrg(String newVal) {
    final old = getAt(0);
    putAt(
        0,
        DataBox(
          name: old!.name,
          org: newVal,
          version: old.version,
        ));
  }

  void updateVersion(int newVal) {
    final old = getAt(0);
    putAt(
        0,
        DataBox(
          name: old!.name,
          org: old.org,
          version: newVal,
        ));
  }
}
