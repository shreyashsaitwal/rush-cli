import 'dart:io' show pid;

import 'package:crypto/crypto.dart';
import 'package:get_it/get_it.dart';
import 'package:path/path.dart' as p;

import 'package:rush/src/commands/build/tools/executor.dart';
import 'package:rush/src/commands/build/toolchain.dart';
import 'package:rush/src/config/config.dart';
import 'package:rush/src/services/ai2_runtime.dart';
import 'package:rush/src/services/file_service.dart';
import 'package:rush/src/services/lib_service.dart';
import 'package:rush/src/services/logger.dart';
import 'package:rush/src/utils/content_key.dart';
import 'package:rush/src/utils/file_extension.dart';

class LibraryDesugarer {
  LibraryDesugarer(this._config);

  final Config _config;
  final _digests = <String, Future<Digest>>{};

  Future<String> desugar(
    String name, {
    required String input,
    required Set<String> classpathJars,
  }) async {
    final dir =
        p.join(GetIt.I<FileService>().rushHomeDir.path, 'cache', 'desugar');
    final key = await _key(input, classpathJars);
    final cached = p.join(dir, '$key.jar');
    if (await cached.asFile().exists()) {
      return cached;
    }

    GetIt.I<Logger>().info('Desugaring $name');
    final partial = p.join(dir.asDir(true).path, '$key.$pid.jar');
    try {
      await Executor.execDesugar(_config,
          input: input, output: partial, classpathJars: classpathJars);
      await partial.asFile().rename(cached);
    } finally {
      if (await partial.asFile().exists()) {
        await partial.asFile().delete();
      }
    }
    return cached;
  }

  Future<String> _key(String input, Set<String> classpathJars) async {
    final key = ContentKey()
      ..add('toolchain', await toolchainKey)
      ..add('min sdk', _config.minSdk)
      ..add('input', await _digest(input))
      ..add('android', await _digest((await Ai2Runtime.load()).androidJar))
      ..add('r8', await _digest(await GetIt.I<LibService>().r8Jar()));
    for (final (i, jar) in classpathJars.indexed) {
      key.add('classpath $i', await _digest(jar));
    }
    return key.value;
  }

  Future<Digest> _digest(String file) => _digests.putIfAbsent(
      file, () async => sha256.convert(await file.asFile().readAsBytes()));
}
