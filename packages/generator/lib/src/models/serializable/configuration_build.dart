import 'package:json_serializer/json_serializer.dart';

class ConfigurationBuild implements Serializable {
  final bool? desugar;
  final bool? minify;
  final bool? optimize;
  final String version;

  ConfigurationBuild({
    this.desugar,
    this.minify,
    this.optimize,
    required this.version,
  });

  @override
  Map<String, dynamic> toMap() {
    return {
      'desugar': desugar,
      'minify': minify,
      'optimize': optimize,
      'version': version,
    };
  }
}
