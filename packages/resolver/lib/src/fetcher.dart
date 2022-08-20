import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:resolver/resolver.dart';
import 'package:resolver/src/errors.dart';
import 'package:resolver/src/model/maven/repository.dart';
import 'package:resolver/src/utils.dart';

import 'model/file_spec.dart';

class ArtifactFetcher {
  Future<DownloadType> _fetch(
      http.Client client, FileSpec spec, Repository repository) async {
    // Return early if the file already exists in the cache.
    if (await File(spec.localFile).exists()) {
      return DownloadType.cache;
    }

    final url = '${repository.url}/${spec.path.replaceAll('\\', '/')}';

    // TODO: Implement hash validation
    try {
      final response = await client.get(Uri.parse(url));
      if (response.statusCode == 200) {
        Utils.writeFile(spec.localFile, response.bodyBytes);
        return DownloadType.download;
      } else {
        throw FetchError(
            message: response.reasonPhrase ?? 'Failed to fetch artifact',
            repositoryId: repository.id,
            responseCode: response.statusCode,
            fileSpec: spec);
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<DownloadType> fetchFile(
      FileSpec fileSpec, Set<Repository> repositories) async {
    final client = http.Client();
    final exceptions = [];

    for (final repo in repositories) {
      try {
        return await _fetch(client, fileSpec, repo);
      } catch (e) {
        exceptions.add(e);
        continue;
      } finally {
        client.close();
      }
    }

    client.close();
    throw exceptions;
  }
}
