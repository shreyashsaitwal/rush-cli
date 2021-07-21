class GhRelease {
  String? body;
  String? name;
  DateTime? publishedAt;

  GhRelease({this.body, this.name, this.publishedAt});

  factory GhRelease.fromJson(Map<dynamic, dynamic> json) => GhRelease(
        body: json['body'] as String?,
        name: json['name'] as String?,
        publishedAt: json['publishedAt'] == null
            ? null
            : DateTime.parse(json['publishedAt'] as String),
      );

  Map<String, dynamic> toJson() => {
        'body': body,
        'name': name,
        'publishedAt': publishedAt?.toIso8601String(),
      };
}
