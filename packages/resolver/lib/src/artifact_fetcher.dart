import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:resolver/src/model/maven/repository.dart';
import 'package:resolver/src/utils.dart';

import 'model/artifact.dart';

class ArtifactFetcher {
  Future<File?> _fetch(http.Client client, FileSpec spec, Repository repository) async {
    final url = '${repository.url}/${spec.path.replaceAll('\\', '/')}';
    File? file;
    try {
      final response = await client.get(Uri.parse(url));
      if (response.statusCode == HttpStatus.ok) {
        file = Utils.writeFile(spec.localFile, response.bodyBytes);
      }
    } catch (e) {
      rethrow;
    }
    return file;
  }

  Future<File?> fetchFile(FileSpec spec, List<Repository> repositories) async {
    final client = http.Client();
    File? file;
    for (final repo in repositories) {
      if (await _fetch(client, spec, repo) != null) {
        file = File(spec.localFile);
        break;
      }
    }
    client.close();
    return file;
  }
}
