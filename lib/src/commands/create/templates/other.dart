import 'package:rush/src/services/lib_service.dart';
import 'package:rush/src/utils/constants.dart';

String config(bool enableKt) {
  return '''
# This is the version name of your extension. You should update it everytime you
# publish a new version of your extension.
version: '1.0.0'

# The minimum Android SDK level your extension supports. Minimum SDK defined in
# AndroidManifest.xml is ignored, you should always define it here.
min_sdk: 21

${!enableKt ? '' : '''

# Kotlin specific configuration.
kotlin:
  compiler_version: '$defaultKtVersion'
'''}
# External libraries your extension depends on. These can be local JARs / AARs
# stored in the "deps" directory or coordinates of remote Maven artifacts in
# <groupId>:<artifactId>:<version> format. AARs are shipped as-is, so their
# resources (layouts, drawables, etc.) are available at runtime.
${enableKt ? 'dependencies:' : '#dependencies:'}
${enableKt ? '- $kotlinGroupId:kotlin-stdlib:$defaultKtVersion\n' : ''}#- example.jar                 # Local JAR or AAR file stored in "deps" directory
#- com.example:foo-bar:1.2.3   # Coordinate of some remote Maven artifact

# Dependencies are resolved from Maven Central and Google's Maven repository. If
# the library you want to use is not available in these repositories, you can
# add additional repositories by specifying their URLs here.
#repositories:
#- https://jitpack.io

# Assets that your extension needs. Every asset file must be stored in the assets
# directory as well as declared here. Assets can be of any type.
#assets:
#- data.json

# Homepage of your extension. This may be the announcement thread on community 
# forums or a link to your GitHub repository.
#homepage: https://github.com/example/my-extension

# Path to the license file of your extension. This should be a path to a local
# file or link to something hosted online.
#license: LICENSE.txt

# Where a library from dependencies goes, when Rush's choice doesn't fit:
# exclude (never resolved), provided (compiled against, not shipped), shared
# (shipped unchanged as an AAR) or private (relocated into the extension). Keys
# are <groupId>:<artifactId>, or file names in the "deps" directory.
#libraries:
#  com.example:foo-bar: provided
''';
}

String pgRules() {
  return '''
# Prevents extension classes (annotated with `@Extension`) from being removed, renamed or repackged.
-keep @com.google.appinventor.components.annotations.Extension public class * {
  public *;
}

# Prevents helper classes from being removed, renamed or repackaged
-keepnames class * implements com.google.appinventor.components.common.OptionList {
  *;
}
''';
}

const String githubWorkflow = r'''
name: Build

on:
  push:
    paths:
      - rush.yml
      - src/**
      - assets/**
      - deps/**
      - res/**
  pull_request:
    paths:
      - rush.yml
      - src/**
      - assets/**
      - deps/**
      - res/**
  workflow_dispatch:

jobs:
  build:
    runs-on: ubuntu-latest
    permissions:
      contents: write
    steps:
      - uses: actions/checkout@v7
      - uses: zainulhassan815/rush-cli@v2
      - run: rush build
      - uses: actions/upload-artifact@v7
        with:
          name: ${{ github.event.repository.name }}
          path: out/
          if-no-files-found: error
      - name: Publish release
        if: startsWith(github.ref, 'refs/tags/v')
        env:
          GH_TOKEN: ${{ github.token }}
        run: |
          version=$(yq .version rush.yml)
          if [ "$GITHUB_REF_NAME" != "v$version" ]; then
            echo "::error::Tag $GITHUB_REF_NAME doesn't match version $version in rush.yml"
            exit 1
          fi
          gh release create "$GITHUB_REF_NAME" out/* --generate-notes
''';

const String dotGitignore = '''
/out
/.rush
/.classpath
/.idea/libraries/
''';

String androidManifestXml(String org) {
  return '''
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="$org">

    <application>
        <!-- You can use any manifest tag that goes inside the <application> tag -->
        <!-- <service android:name="com.example.MyService"> ... </service> -->
    </application>

    <!-- Other than <application> level tags, you can use <uses-permission> & <queries> tags -->
    <!-- <uses-permission android:name="android.permission.SEND_SMS"/> -->
    <!-- <queries> ... </queries> -->

</manifest>
''';
}

String readmeMd(String name) {
  return '''
# $name

An App Inventor 2 extension created using [Rush](https://github.com/zainulhassan815/rush-cli).

## Building

Run `rush build` in this directory. The extension is written to the `out`
directory as an `.aix` file, ready to import into App Inventor.

Run `rush build --optimize` to also optimize and obfuscate the extension's code.

## Releasing

GitHub Actions builds the extension when a push or pull request changes it. To publish
a release, push a tag named after the version in `rush.yml`, like `v1.0.0`.
The workflow attaches the `.aix` file and its documentation to the release.
''';
}
