import 'package:generator/src/models/serializable/configuration_build.dart';
import 'package:json_serializer/json_serializer.dart';

class Configuration implements Serializable {
  final List<String>? assets;
  final ConfigurationBuild build;
  final Map<String, List<String>>? dependencies;

  final String description;
  final String icon;
  final String name;

  Configuration({
    this.assets,
    required this.build,
    this.dependencies,
    required this.description,
    required this.icon,
    required this.name,
  });

  @override
  Map<String, dynamic> toMap() {
    return {
      'assets': assets,
      'build': build,
      'dependencies': dependencies,
      'description': description,
      'icon': icon,
      'name': name,
    };
  }
}
