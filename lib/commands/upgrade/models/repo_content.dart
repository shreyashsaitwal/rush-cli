part 'links.dart';

class RepoContent {
  String? name;
  String? path;
  String? sha;
  int? size;
  String? url;
  String? htmlUrl;
  String? gitUrl;
  String? downloadUrl;
  String? type;
  Links? links;

  RepoContent({
    this.name,
    this.path,
    this.sha,
    this.size,
    this.url,
    this.htmlUrl,
    this.gitUrl,
    this.downloadUrl,
    this.type,
    this.links,
  });

  factory RepoContent.fromJson(Map<dynamic, dynamic> json) => RepoContent(
        name: json['name'] as String?,
        path: json['path'] as String?,
        sha: json['sha'] as String?,
        size: json['size'] as int?,
        url: json['url'] as String?,
        htmlUrl: json['html_url'] as String?,
        gitUrl: json['git_url'] as String?,
        downloadUrl: json['download_url'] as String?,
        type: json['type'] as String?,
        links: json['_links'] == null
            ? null
            : Links.fromJson(json['_links'] as Map<String, dynamic>),
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'path': path,
        'sha': sha,
        'size': size,
        'url': url,
        'html_url': htmlUrl,
        'git_url': gitUrl,
        'download_url': downloadUrl,
        'type': type,
        '_links': links?.toJson(),
      };
}
