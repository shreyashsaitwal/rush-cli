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
own, and `rush deps tree` prints what was resolved, where each library goes and why (see
[How libraries are shipped](#how-libraries-are-shipped)):

```
counter
└──┬ com.google.code.gson:gson:2.13.1 (private: default)
   └─── com.google.errorprone:error_prone_annotations:2.38.0 (private: default)
```

## Placing libraries

Every library the extension ships is private unless `libraries` places it elsewhere,
for a library you depend on directly or one pulled in by another:

```yaml
dependencies:
- io.github.jan-tennert.supabase:postgrest-kt-jvm:3.8.0
- com.example:host-api:1.2

libraries:
  org.jetbrains.kotlin:kotlin-reflect: exclude
  com.example:host-api: provided
```

Keys are `group:artifact`, without a version, or file names in `deps`. Each library goes
to one of:

- **`exclude`**: never resolved, nor what only it needs. Neither compiled against nor
  shipped. A library listed in `dependencies` can't be excluded: remove it instead. When
  code you ship still references it, R8 reports `Missing class`; if that code never runs,
  say so in `src/proguard-rules.pro`. For example, Ktor's server
  code references `kotlin-reflect`:

  ```
  -dontwarn kotlin.reflect.full.**
  -dontwarn kotlin.reflect.jvm.**
  ```
- **`provided`**: compiled against but not shipped, nor what only it needs, for
  libraries that are already present at runtime. The version comes from `dependencies`,
  so a compile-only library you don't otherwise depend on goes there too.
- **`shared`**: shipped unchanged as an AAR; App Inventor keeps one copy for every
  extension in the app. What it depends on is shared too. Place a library as `shared`
  when its objects pass between extensions, or when it can't be private.
- **`private`**, the default: the extension's own copy, renamed into it (see
  [How libraries are shipped](#how-libraries-are-shipped)). Rush refuses it, naming the
  `shared` entry to add, for an AAR with assets (they keep their paths) or JARs in
  `libs/` (they aren't renamed), and for a library a shared library uses by its
  original name. An AAR with native libraries can be private once the packages its
  native code names keep their names (see
  [Keeping original names](#keeping-original-names)).

A key that matches no library is a warning, as it's likely a typo.

`provided_dependencies`, which earlier versions used for compile-only libraries, still
works but is deprecated: `rush migrate` moves its entries to `dependencies`, placed as
`provided`.

## Keeping original names

Private libraries' classes are renamed into the extension. Code that finds a class by
name from outside the bytecode, such as a native library binding its JNI functions, can't
follow the new name. List the packages that must keep their names under
`original_names`:

```yaml
original_names:
- androidx.datastore.core
```

Their classes keep their names, and R8 keeps them whole, members included. Whole
packages are kept because Java's package-private access works only inside one package.

A private AAR with native libraries ships as an AAR, so its `.so` files ship with it, and
R8 keeps its classes whole, since native code calls into classes R8 can't see used.
Rush reads its `.so` files for the classes they name, by JNI function or by name, and
stops the build when their packages aren't listed, printing the lines to add. Native
code that builds class names at runtime can't be read this way; list those packages
too.
Kept classes can clash with another extension that ships the same ones, so keep as few
packages as possible. A listed package that no private library has is an error.

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
runtime. Annotations are the exception: recent libraries use ones App Inventor's
`androidx.annotation` lacks, such as `DoNotInline`, which are needed only to compile.
R8 reports them as missing; `rush create` adds `-dontwarn androidx.annotation.**` to new
projects' `src/proguard-rules.pro`, and older projects need that line too. Libraries built on recent AndroidX, such as Jetpack Compose, can't work in App
Inventor.

Other libraries in App Inventor's runtime, such as Guava, Gson and RecyclerView, are on
the compile classpath but only included in apps that use a component needing them. Code
that uses them compiles without declaring them, then fails with `NoClassDefFoundError`
in other apps. Declare every library your extension uses in `dependencies`.

## How libraries are shipped

App Inventor puts every extension's code into one app, with its own libraries and those
of other extensions, and Kodular adds its own. Two copies of a class clash
(`defined multiple times`), and when two AARs share a package App Inventor keeps the
first, whatever its version. So Rush renames private libraries into the extension,
under `<package>.repacked` (`com.example.counter.repacked.…`):

- **Code** of private JARs and AARs is shrunk with the extension's to what it uses (see
  [Optimizing](building.md#optimizing)) and moved under that package. Rush also rewrites
  strings that name a moved class, so reflection on them keeps working.
- **AARs with resources** ship as renamed AARs (`com.example.counter.repacked.<file>.aar`):
  their manifest package, the classes their manifests and layouts name, and their
  resources, prefixed with `com_example_counter_repacked_`, so another copy of the
  same library, in any version, can't collide with them. An AAR without resources joins
  the extension's code.
- **Shared libraries** ship unchanged as AARs, and JARs they depend on are wrapped into
  their own small AARs. App Inventor keeps one copy of each per app.

Some names must stay as they are:

- **Resources App Inventor's AndroidX also defines**, such as the `icon` attribute that
  AppCompat and Material both declare, keep their names, so both libraries keep using
  one resource as in any Android app.
- **Intent actions and categories** in the extension's manifest and in private AARs'
  manifests keep their value, in the manifest and in code, even when they equal a class
  name: other apps and the system send them. Media3's
  `androidx.media3.session.MediaSessionService` action is one.
- **Native code and assets** find classes and files by their original names, and JARs
  bundled in an AAR's `libs/` aren't renamed, which is why AARs with them must be
  shared.

Renamed classes and resources change the app's code the first time an extension is
rebuilt with private libraries. What an installed app stored under the old names, such
as scheduled jobs or widgets naming a library's component, or data serialized with
class names, isn't found after the update.

App Inventor de-duplicates AARs against AARs only. Some of its own libraries, such as
MPAndroidChart for the Chart component or Guava for Texting, are added as plain JARs to
apps that use the matching built-in component. A private copy can't clash with them. A
shared one can: if a shared AAR uses such a library, apps can't combine the extension
with that component until App Inventor de-duplicates its libraries; say so in the
extension's documentation.

Extensions that ship AARs work in built apps but not in the AI Companion, which can't
load them.

## What App Inventor leaves out

Only classes reach the app. Java resources in a library's JAR, or in an AAR's
`classes.jar`, don't: Rush keeps only classes, and App Inventor doesn't package them
either. AAR `assets/`, `jni/` and resources are packaged and work.

Two kinds of libraries notice:

- Libraries that find implementations with `ServiceLoader`, listed in
  `META-INF/services/`. They find none, except in [optimized](building.md#optimizing)
  builds of private libraries that call `ServiceLoader.load(X.class,
  X.class.getClassLoader())`, which R8 replaces with the implementations.
- Libraries that read a file with `getResource`, such as OkHttp's public suffix list.

To find them, list a library's JAR (or an AAR's `classes.jar`) and look for
`META-INF/services/` and files outside `META-INF`. Whether the code that reads them runs
depends on how you use the library; coroutines, for example, works without its
services. If it does run:

- Give the library what it would have looked up, if it lets you. For example, create
  Ktor's client with an engine, `HttpClient(OkHttp)`, instead of `HttpClient()`.
- Or leave the library out, with [`exclude`](#placing-libraries). Without
  `kotlin-reflect`, for example, `typeOf<T>()` falls back to the standard library's own
  implementation.

Rush warns when two AARs are the same library, such as a Maven library and a copy of it
in `deps`: only one of them can ship.

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
