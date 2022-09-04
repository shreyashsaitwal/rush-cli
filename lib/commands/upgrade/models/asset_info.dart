class Asset {
  final String name;
  final String sha1;
  final String url;
  final String downloadLocation;

  Asset({
    required this.name,
    required this.sha1,
    required this.url,
    required this.downloadLocation,
  });

  factory Asset.fromJson(Map<String, String> json) => Asset(
        name: json['name']!,
        sha1: json['sha1']!,
        url: json['url']!,
        downloadLocation: json['download_location']!,
      );
}

class AssetInfo {
  final List<Asset> assets;

  AssetInfo(this.assets);

  factory AssetInfo.fromJson(List<Map<String, String>> json) {
    return AssetInfo(json.map((e) => Asset.fromJson(e)).toList());
  }
}
