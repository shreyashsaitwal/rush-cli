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
  final res = ArtifactResolver();
  final times = <int>[];

  for (final spec in androidxArtifacts) {
    final start = DateTime.now();
    final _ = await res.resolvePom(spec);
    times.add(DateTime.now().difference(start).inMilliseconds);
    print('$spec ==> ${times.last}ms');
  }

  print('Average ==> ${times.reduce((a, b) => a + b) / times.length}ms');
}