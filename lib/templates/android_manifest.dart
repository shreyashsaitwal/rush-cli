String getManifestXml(String org) {
  return '''
<?xml version="1.0" encoding="utf-8"?>
<manifest
    xmlns:android="http://schemas.android.com/apk/res/android"
    package="$org">

    <!-- For more details, see: https://github.com/ShreyashSaitwal/rush-cli/wiki/Android-Manifest-File -->

    <application>
      <!-- <activity android:name=".MainActivity">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity> -->
    </application>
</manifest>
''';
}
