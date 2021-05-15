class BinData {
  String path;
  String download;
  int size;

  BinData(this.path, this.download, this.size);

  factory BinData.fromJson(Map<String, dynamic> json) {
    return BinData(
      json['path'] as String,
      json['download'] as String,
      json['size'] as int,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'path': path,
      'download': download,
    };
  }
}
