# Android manifest

`src/AndroidManifest.xml` declares what the extension adds to every app that uses it:
permissions, activities, services and so on. App Inventor merges these entries into the
app's manifest.

```xml
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="com.example.counter">
    <application>
        <service android:name="com.example.counter.PlaybackService"
            android:exported="false"/>
    </application>

    <uses-permission android:name="android.permission.INTERNET"/>
    <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE"
        android:maxSdkVersion="32"/>

    <uses-feature android:name="android.hardware.camera" android:required="false"/>

    <queries>
        <package android:name="com.example.app"/>
    </queries>
</manifest>
```

## What reaches the app

| Entry | Notes |
|---|---|
| `<uses-permission>` | Including `android:maxSdkVersion` and `android:usesPermissionFlags`. |
| Children of `<application>` | `<activity>`, `<activity-alias>`, `<service>`, `<receiver>`, `<provider>`, `<meta-data>`, `<uses-library>`, `<uses-native-library>` and `<profileable>`. |
| `<uses-feature>` | |
| Children of `<queries>` | |

Everything else, such as `<uses-sdk>` or `<permission>`, is ignored: set the minimum
Android version with [`min_sdk`](configuration.md#min_sdk) in `rush.yml`.

`tools:` attributes are removed, and `${applicationId}` is replaced with the app's
package name, so providers can declare unique authorities:

```xml
<provider android:name="androidx.core.content.FileProvider"
    android:authorities="${applicationId}.counter.files"
    android:exported="false"
    android:grantUriPermissions="true"/>
```

`android:maxSdkVersion` on `WRITE_EXTERNAL_STORAGE` is ignored with a warning, because
App Inventor already limits that permission to Android 10.

## AAR manifests

When the extension [ships AARs](dependencies.md#how-libraries-are-shipped), their
manifests are merged into the extension's, the same way Android Studio merges library
manifests. A library's permissions, activities and services therefore reach the app
without being copied into `src/AndroidManifest.xml`. `${applicationId}` in a library's
manifest becomes the app's package too, so apps that use the same extension can be
installed side by side.

## Runtime permissions

Dangerous permissions, such as the camera or location, must also be requested while the
app runs. App Inventor's form does it for you:

```java
form.askPermission(Manifest.permission.CAMERA, (permission, granted) -> {
  if (granted) {
    startCamera();
  }
});
```

If a block needs a permission the user denied, throw
`PermissionException(permission)` from it: App Inventor then fires the screen's
`PermissionDenied` event.
