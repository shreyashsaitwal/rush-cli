import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:resolver/src/model/maven/repository.dart';
import 'package:resolver/src/utils.dart';

import 'model/artifact.dart';

class ArtifactFetcher {
  Future<bool> _fetch(FileSpec spec, Repository repository) async {
    final url = '${repository.url}/${spec.path.replaceAll('\\', '/')}';
    final client = http.Client();
    try {
      final response = await client.get(Uri.parse(url));
      if (response.statusCode == HttpStatus.ok) {
        Utils.writeFile(spec.localFile, response.bodyBytes);
        return true;
      }
    } catch (e) {
      print(e);
    }
    return false;
  }

  Future<void> fetchFile(FileSpec spec, List<Repository> repositories) async {
    for (final repo in repositories) {
      if (await _fetch(spec, repo)) {
        return;
      }
    }
  }
}
