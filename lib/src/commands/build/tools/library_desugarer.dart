import 'package:collection/collection.dart';
import 'package:crypto/crypto.dart';
import 'package:get_it/get_it.dart';

import 'package:rush/src/commands/build/tools/executor.dart';
import 'package:rush/src/config/config.dart';
import 'package:rush/src/services/ai2_runtime.dart';
import 'package:rush/src/services/lib_service.dart';
import 'package:rush/src/utils/file_extension.dart';
import 'package:rush/src/version.dart';

class LibraryDesugarer {
  LibraryDesugarer(this._config);

  final Config _config;
  final _digests = <String, Future<Digest>>{};

  Future<void> desugar({
    required String input,
    required String output,
    required Set<String> classpathJars,
  }) async {
    final key = await _key(input, classpathJars);
    final keyFile = '$output.key'.asFile();
    if (await output.asFile().exists() &&
        await keyFile.exists() &&
        await keyFile.readAsString() == key) {
      return;
    }

    if (await keyFile.exists()) {
      await keyFile.delete();
    }
    await Executor.execDesugar(_config,
        input: input, output: output, classpathJars: classpathJars);
    await keyFile.writeAsString(key);
  }

  Future<String> _key(String input, Set<String> classpathJars) async {
    final files = [
      input,
      (await Ai2Runtime.load()).androidJar,
      await GetIt.I<LibService>().r8Jar(),
      ...classpathJars.sorted(),
    ];
    final digests = await Future.wait(files.map(_digest));
    return [
      packageVersion,
      _config.minSdk,
      for (final (i, file) in files.indexed) '$file ${digests[i]}',
    ].join('\n');
  }

  Future<Digest> _digest(String file) => _digests.putIfAbsent(
      file, () async => sha256.convert(await file.asFile().readAsBytes()));
}
