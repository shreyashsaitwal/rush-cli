# Dependencies

## Declaring dependencies

List libraries in `rush.yml` as Maven coordinates (`group:artifact:version`) or as file
names of JARs and AARs stored in the `deps` directory:

```yaml
dependencies:
- com.google.code.gson:gson:2.13.1
- androidx.media3:media3-exoplayer:1.11.1
- my-library.jar
```

Rush resolves Maven dependencies, with their own dependencies, from Maven Central and
Google's Maven repository, plus any repositories you add:

```yaml
repositories:
- https://jitpack.io
```

Downloads are stored in the local Maven repository (`~/.m2/repository`, or
`$M2_HOME/repository`), which is also searched first. Local files in `deps` don't bring
their own dependencies: list those too.

`rush build` syncs dependencies when `rush.yml` changes. `rush deps sync` does it on its
own, and `rush deps tree` prints what was resolved:

```
counter
└──┬ com.google.code.gson:gson:2.13.1 (compile)
   └─── com.google.errorprone:error_prone_annotations:2.38.0 (compile)
```

## Provided dependencies

`provided_dependencies` are compiled against but never shipped, for libraries that are
already present at runtime:

```yaml
provided_dependencies:
- some-sdk-stubs.jar
```

## What App Inventor provides

Every app contains App Inventor's runtime, Kawa and these AndroidX libraries, which Rush
never bundles:

annotation 1.0.0, annotation-experimental 1.3.0, appcompat 1.0.0, arch core 2.0.0,
asynclayoutinflater, collection 1.0.0, constraintlayout 1.1.3, coordinatorlayout,
core 1.9.0, cursoradapter, customview, documentfile, drawerlayout, fragment 1.0.0,
interpolator, legacy-support-core-ui and -utils, lifecycle 2.0.0 (common, livedata,
runtime, viewmodel), loader, localbroadcastmanager, print, slidingpanelayout,
swiperefreshlayout, vectordrawable, versionedparcelable and viewpager.

These versions date from 2018 and always win: when a dependency needs a newer one, Rush
warns that App Inventor's older version will be used, and calls into newer APIs fail at
runtime. Libraries built on recent AndroidX, such as Jetpack Compose, can't work in App
Inventor.

Other libraries in App Inventor's runtime, such as Guava, Gson and RecyclerView, are on
the compile classpath but only included in apps that use a component needing them. Code
that uses them compiles without declaring them, then fails with `NoClassDefFoundError`
in other apps. Declare every library your extension uses in `dependencies`.

## How libraries are shipped

App Inventor puts every extension's code into one app, so two extensions bundling the
same library would clash (`defined multiple times`). Rush avoids this:

- **AARs** are shipped as AARs inside the AIX. App Inventor compiles their resources and
  includes each one only once per app, by package name: when two extensions ship the
  same library, the first copy wins, whatever its version.
- **JARs that a shipped AAR depends on** are wrapped into their own small AARs, so they
  are shared the same way.
- **All other JARs** are merged into the extension, shrunk to the code it uses, and
  moved under the extension's package (`com.example.counter.repacked.…`), so they can't
  clash with another extension's copy. Rush also rewrites strings that name a moved
  class.

Extensions that ship AARs work in built apps but not in the AI Companion, which can't
load them.

Rush warns when two shipped AARs are the same library, since App Inventor would keep an
arbitrary one.

## Kotlin

Kotlin projects need the standard library as a dependency. `rush create` adds it:

```yaml
kotlin:
  compiler_version: '2.4.20'

dependencies:
- org.jetbrains.kotlin:kotlin-stdlib:2.4.20
```

It's moved under the extension's package like any other library, so extensions using
different Kotlin versions work together.

## ProGuard rules from libraries

Libraries' consumer rules, `proguard.txt` in AARs and `META-INF/proguard/*.pro` in JARs,
are applied when Rush shrinks and [optimizes](building.md#optimizing) the extension.
