part of 'repo_content.dart';

class Links {
  String? self;
  String? git;
  String? html;

  Links({this.self, this.git, this.html});

  factory Links.fromJson(Map<String, dynamic> json) => Links(
        self: json['self'] as String?,
        git: json['git'] as String?,
        html: json['html'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'self': self,
        'git': git,
        'html': html,
      };
}
