import 'package:path/path.dart' as path;

String getDotClasspath(String appStorageDir) {
  return '''
<?xml version="1.0" encoding="UTF-8"?>
<classpath>
	<classpathentry kind="src" path="_/src"/>
  <classpathentry kind="lib" path="${path.join(appStorageDir, 'acra-4.4.0.jar')}"/>
  <classpathentry kind="lib" path="${path.join(appStorageDir, 'android.jar')}"/>
  <classpathentry kind="lib" path="${path.join(appStorageDir, 'AndroidRuntime.jar')}"/>
  <classpathentry kind="lib" path="${path.join(appStorageDir, 'androidsvg.jar')}"/>
  <classpathentry kind="lib" path="${path.join(appStorageDir, 'annotation.jar')}"/>
  <classpathentry kind="lib" path="${path.join(appStorageDir, 'AnnotationProcessors.jar')}"/>
  <classpathentry kind="lib" path="${path.join(appStorageDir, 'appcompat.jar')}"/>
  <classpathentry kind="lib" path="${path.join(appStorageDir, 'asynclayoutinflater.jar')}"/>
  <classpathentry kind="lib" path="${path.join(appStorageDir, 'Barcode.jar')}"/>
  <classpathentry kind="lib" path="${path.join(appStorageDir, 'collection.jar')}"/>
  <classpathentry kind="lib" path="${path.join(appStorageDir, 'commons-pool.jar')}"/>
  <classpathentry kind="lib" path="${path.join(appStorageDir, 'CommonVersion.jar')}"/>
  <classpathentry kind="lib" path="${path.join(appStorageDir, 'constraintlayout-solver.jar')}"/>
  <classpathentry kind="lib" path="${path.join(appStorageDir, 'constraintlayout.jar')}"/>
  <classpathentry kind="lib" path="${path.join(appStorageDir, 'coordinatorlayout.jar')}"/>
  <classpathentry kind="lib" path="${path.join(appStorageDir, 'core-common.jar')}"/>
  <classpathentry kind="lib" path="${path.join(appStorageDir, 'core-runtime.jar')}"/>
  <classpathentry kind="lib" path="${path.join(appStorageDir, 'core.jar')}"/>
  <classpathentry kind="lib" path="${path.join(appStorageDir, 'cursoradapter.jar')}"/>
  <classpathentry kind="lib" path="${path.join(appStorageDir, 'customview.jar')}"/>
  <classpathentry kind="lib" path="${path.join(appStorageDir, 'documentfile.jar')}"/>
  <classpathentry kind="lib" path="${path.join(appStorageDir, 'drawerlayout.jar')}"/>
  <classpathentry kind="lib" path="${path.join(appStorageDir, 'firebase.jar')}"/>
  <classpathentry kind="lib" path="${path.join(appStorageDir, 'fragment.jar')}"/>
  <classpathentry kind="lib" path="${path.join(appStorageDir, 'fusiontables.jar')}"/>
  <classpathentry kind="lib" path="${path.join(appStorageDir, 'generate.dart')}"/>
  <classpathentry kind="lib" path="${path.join(appStorageDir, 'google-api-client-android2-beta.jar')}"/>
  <classpathentry kind="lib" path="${path.join(appStorageDir, 'google-api-client-beta.jar')}"/>
  <classpathentry kind="lib" path="${path.join(appStorageDir, 'google-http-client-android2-beta.jar')}"/>
  <classpathentry kind="lib" path="${path.join(appStorageDir, 'google-http-client-android3-beta.jar')}"/>
  <classpathentry kind="lib" path="${path.join(appStorageDir, 'google-http-client-beta.jar')}"/>
  <classpathentry kind="lib" path="${path.join(appStorageDir, 'google-oauth-client-beta.jar')}"/>
  <classpathentry kind="lib" path="${path.join(appStorageDir, 'gson-2.1.jar')}"/>
  <classpathentry kind="lib" path="${path.join(appStorageDir, 'guava-14.0.1.jar')}"/>
  <classpathentry kind="lib" path="${path.join(appStorageDir, 'http-legacy.jar')}"/>
  <classpathentry kind="lib" path="${path.join(appStorageDir, 'httpmime.jar')}"/>
  <classpathentry kind="lib" path="${path.join(appStorageDir, 'interpolator.jar')}"/>
  <classpathentry kind="lib" path="${path.join(appStorageDir, 'jedis.jar')}"/>
  <classpathentry kind="lib" path="${path.join(appStorageDir, 'json.jar')}"/>
  <classpathentry kind="lib" path="${path.join(appStorageDir, 'jts.jar')}"/>
  <classpathentry kind="lib" path="${path.join(appStorageDir, 'kawa.jar')}"/>
  <classpathentry kind="lib" path="${path.join(appStorageDir, 'legacy-support-core-ui.jar')}"/>
  <classpathentry kind="lib" path="${path.join(appStorageDir, 'legacy-support-core-utils.jar')}"/>
  <classpathentry kind="lib" path="${path.join(appStorageDir, 'lifecycle-common.jar')}"/>
  <classpathentry kind="lib" path="${path.join(appStorageDir, 'lifecycle-livedata-core.jar')}"/>
  <classpathentry kind="lib" path="${path.join(appStorageDir, 'lifecycle-livedata.jar')}"/>
  <classpathentry kind="lib" path="${path.join(appStorageDir, 'lifecycle-runtime.jar')}"/>
  <classpathentry kind="lib" path="${path.join(appStorageDir, 'lifecycle-viewmodel.jar')}"/>
  <classpathentry kind="lib" path="${path.join(appStorageDir, 'loader.jar')}"/>
  <classpathentry kind="lib" path="${path.join(appStorageDir, 'localbroadcastmanager.jar')}"/>
  <classpathentry kind="lib" path="${path.join(appStorageDir, 'osmdroid.jar')}"/>
  <classpathentry kind="lib" path="${path.join(appStorageDir, 'physicaloid.jar')}"/>
  <classpathentry kind="lib" path="${path.join(appStorageDir, 'print.jar')}"/>
  <classpathentry kind="lib" path="${path.join(appStorageDir, 'QRGenerator.jar')}"/>
  <classpathentry kind="lib" path="${path.join(appStorageDir, 'slidingpanelayout.jar')}"/>
  <classpathentry kind="lib" path="${path.join(appStorageDir, 'swiperefreshlayout.jar')}"/>
  <classpathentry kind="lib" path="${path.join(appStorageDir, 'twitter4j.jar')}"/>
  <classpathentry kind="lib" path="${path.join(appStorageDir, 'twitter4jmedia.jar')}"/>
  <classpathentry kind="lib" path="${path.join(appStorageDir, 'vectordrawable-animated.jar')}"/>
  <classpathentry kind="lib" path="${path.join(appStorageDir, 'vectordrawable.jar')}"/>
  <classpathentry kind="lib" path="${path.join(appStorageDir, 'versionedparcelable.jar')}"/>
  <classpathentry kind="lib" path="${path.join(appStorageDir, 'viewpager.jar')}"/>
  <classpathentry kind="output" path="bin"/>
</classpath>

  ''';
}