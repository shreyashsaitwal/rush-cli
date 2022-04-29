import 'dart:io';

import 'package:resolver/resolver.dart';

Future<void> main(List<String> args) async {
  final androidxArtifacts = [
    'androidx.annotation:annotation:1.0.0',
    'androidx.appcompat:appcompat:1.0.0',
    'androidx.asynclayoutinflater:asynclayoutinflater:1.0.0',
    'androidx.collection:collection:1.0.0',
    'androidx.constraintlayout:constraintlayout:1.1.0',
    'androidx.coordinatorlayout:coordinatorlayout:1.0.0',
    'androidx.core:core:1.0.0',
    'androidx.cursoradapter:cursoradapter:1.0.0',
    'androidx.arch.core:core-common:2.0.0',
    'androidx.arch.core:core-runtime:2.0.0',
    'androidx.customview:customview:1.0.0',
    'androidx.drawerlayout:drawerlayout:1.0.0',
    'androidx.fragment:fragment:1.0.0',
    'androidx.interpolator:interpolator:1.0.0',
    'androidx.lifecycle:lifecycle-common:2.0.0',
    'androidx.lifecycle:lifecycle-livedata:2.0.0',
    'androidx.lifecycle:lifecycle-runtime:2.0.0',
    'androidx.legacy:legacy-support-core-ui:1.0.0',
    'androidx.legacy:legacy-support-core-utils:1.0.0',
    'androidx.loader:loader:1.0.0',
    'androidx.localbroadcastmanager:localbroadcastmanager:1.0.0',
    'androidx.print:print:1.0.0',
  ];
  // final time = <int>[];

  // final resolver = ArtifactResolver();
  // for (final artifact in androidxArtifacts) {
  //   final start = DateTime.now();
  //   final model = await resolver.resolve(resolver.artifactFor(artifact));
  //   time.add(DateTime.now().difference(start).inMilliseconds);
  //   print('$artifact: ${time.last}');
  // }

  // // average time
  // final average = time.reduce((a, b) => a + b) / time.length;
  // print('Average time: ${average}ms');
  // print('Total time: ${time.reduce((a, b) => a + b)}ms');

  final futures = <Future>[];

  final start = DateTime.now();
  final resolver = ArtifactResolver();
  for (final artifact in androidxArtifacts) {
    futures.add(resolver.resolve(resolver.artifactFor(artifact)));
  }

  await Future.wait(futures).whenComplete(() => print(
      'Total time: ${DateTime.now().difference(start).inMilliseconds}ms'));
}
