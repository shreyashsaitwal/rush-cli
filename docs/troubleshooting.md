# Troubleshooting

## Build errors

**`Could not run javac`** (or `java`). Rush needs a JDK, version 17 or newer. It runs
`java` and `javac` from `JAVA_HOME`, or from `PATH` when `JAVA_HOME` isn't set.

**`BUILD FAILED` without an error message.** Run the build again with `--verbose` to see
what failed.

**`error: release version 17 not supported`.** The JDK is older than 17. Install JDK 17
or newer, and point `JAVA_HOME` to it.

**`Could not find Rush data directory at …`.** Rush isn't installed where it expects, or
`RUSH_HOME` points to the wrong directory. Re-run the installer.

**`App Inventor runtime v206 is not installed.`** Run `rush deps sync --dev-deps`.

**`Downloading … stalled`.** A download made no progress for 30 seconds. Check your
connection and run the command again.

**`Unable to resolve dependencies`** or **`Unable to find artifact file for …`.** Check
the coordinates in `rush.yml`, and add the library's repository under `repositories` if
it isn't on Maven Central or Google's Maven repository.

**`Unable to find components.json or component_build_infos.json`.** No class has
`@Extension`. See [The extension class](writing-extensions.md#the-extension-class).

**`All extensions in a project must be in the same package`.** Move the extension
classes into one package.

**`Found use of boxed type java.lang.Integer. Please use the primitive type int instead.`**
Blocks take and return primitives. See [Block types](writing-extensions.md#block-types).

**`Cannot convert Java type '…' to YAIL type.`** The type can't be a block's parameter or
result. Use one of the [block types](writing-extensions.md#block-types).

**`Dropdown enum … must be in a directory named helpers`.** Move the enum into a
`helpers` directory. See [Dropdowns](writing-extensions.md#dropdowns).

**`string/title must be named com_example_counter_title`.** Resource names must start
with the extension's package. See [Naming](resources.md#naming).

**`Icon file assets/… not found.`** The `icon` of `@Extension` must be a file in
`assets`, or a URL.

**`Missing class …`.** Code the extension ships uses a class that nothing ships. Add the
library that provides it to `dependencies`, or, if that code never runs, add `-dontwarn`
rules for it to `src/proguard-rules.pro`. See [Optimizing](building.md#optimizing).

**`src/proguard-rules.pro sets -repackageclasses`.** Rush moves optimized classes under
the extension's package itself. Remove the rule, or run `rush migrate`.

**`Asset … does not exist`.** A file listed under `assets` in `rush.yml` is missing from
the `assets` directory.

## Warnings

**`… is required, but App Inventor provides an older version (…) which will be used
instead.`** A dependency needs a newer AndroidX library than App Inventor's. Use an older
version of the dependency that works with App Inventor's, or test the features you use
carefully. See [What App Inventor provides](dependencies.md#what-app-inventor-provides).

**`… ships files App Inventor leaves out of the app, so code that loads them won't find
them: …`.** The library reads files that never reach the app, through `ServiceLoader` or
`getResource`. See [What App Inventor leaves out](dependencies.md#what-app-inventor-leaves-out).

**`… and … are the same library (…). App Inventor includes only one of them in the
app`.** Two shipped AARs have the same package. Keep one of them in `rush.yml`.

## In App Inventor

**The app build fails with `defined multiple times`.** Two extensions contain the same
class. This happens with extensions built by Rush 1, Rush 2.0 or other tools, which
bundled libraries without moving them. Rebuild them with this Rush, or remove one.

**The extension works in a built app but not in the AI Companion.** The Companion can't
load AARs, so extensions with [resources](resources.md) or AAR dependencies only work in
built apps.

**`NoClassDefFoundError` or `ClassNotFoundException` at runtime.** The extension uses a
library it doesn't declare, such as Guava or Gson, which App Inventor only includes in
some apps. Add it to `dependencies`.

**`NoSuchMethodError` in an AndroidX class.** A library expects a newer AndroidX than App
Inventor's, whose version always wins. See
[What App Inventor provides](dependencies.md#what-app-inventor-provides).

**An event doesn't fire when the app starts.** App Inventor drops events fired while
`Screen.Initialize` runs. [Post them to the main looper](writing-extensions.md#events).
