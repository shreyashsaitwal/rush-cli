import 'dart:io' show Platform;

import 'package:path/path.dart' as p;

import 'package:rush/src/commands/build/utils.dart';
import 'package:rush/src/utils/content_key.dart';
import 'package:rush/src/version.dart';

final Future<String> toolchainKey = () async {
  final key = ContentKey()..add('rush', packageVersion);
  await key.addFile('rush executable', Platform.resolvedExecutable);
  await key.addPath('jdk', p.join(await BuildUtils.javaHomeDir(), 'release'));
  return key.value;
}();
