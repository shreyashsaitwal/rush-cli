# Troubleshooting

## Build errors

**`Could not run javac`** (or `java`). Rush needs a JDK, version 17 or newer. It runs
`java` and `javac` from `JAVA_HOME`, or from `PATH` when `JAVA_HOME` isn't set.

**`BUILD FAILED` without an error message.** Run the build again with `--verbose` to see
what failed.

**`error: release version 17 not supported`.** The JDK is older than 17. Install JDK 17
or newer, and point `JAVA_HOME` to it.

**`Could not find Rush data directory at …`.** The directory has no `libs`: `RUSH_HOME` (if set)
points to the wrong directory, or Rush's install is incomplete. Re-run the installer.

**`App Inventor runtime v206 is not installed.`** Run `rush deps sync --dev-deps`.

**`Downloading … stalled`.** A download made no progress for 30 seconds. Check your
connection and run the command again.

**`Unable to resolve dependencies`** or **`Unable to find artifact file for …`.** Check
the coordinates in `rush.yml`, and add the library's repository under `repositories` if
it isn't on Maven Central or Google's Maven repository.

**`No extension found`.** No class has `@Extension`. See
[The extension class](writing-extensions.md#the-extension-class).

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

**`… is listed in rush.yml but doesn't exist`.** A file listed under `assets` or
`dependencies` in `rush.yml` is missing from the `assets` or `deps` directory.

**`Functions with continuation must be void.`** A function that takes a `Continuation`
delivers its result through it. See [Continuations](writing-extensions.md#continuations).

**`… can't start with …_repacked_, which Rush gives the resources of private
libraries`.** Rename the resource: names like `com_example_counter_repacked_icon` are
reserved for private libraries. See [Resources](resources.md).

**`… can't be private: its assets keep their original paths` or `the JARs in its libs/
folder keep their original names`.** Add the `shared` entry the message names to
`libraries` in `rush.yml`. What the library uses becomes shared too.

**`… can't be private: … ships unchanged and uses it by its original name`.** A shared
library uses this library, so it can't be private. Remove its entry from `libraries` in
`rush.yml`.

**`… has native libraries that find classes in … by their original names`.** Add the
packages the message lists under `original_names` in `rush.yml`, or place the library as
`shared`. See [Keeping original names](dependencies.md#keeping-original-names).

**`original_names lists …, but no private library has classes in it`.** Remove the
package from `original_names`.

## Warnings

**`… is required, but App Inventor provides an older version (…) which will be used
instead.`** A dependency needs a newer AndroidX library than App Inventor's. Use an older
version of the dependency that works with App Inventor's, or test the features you use
carefully. See [What App Inventor provides](dependencies.md#what-app-inventor-provides).

**`… and … are the same library (…), so only one of them can ship`.** Two AARs have the
same package, such as a Maven library and a copy of it in `deps`. Keep one of them in
`rush.yml`.

**`Missing class androidx.annotation.…`.** Recent libraries use annotations App
Inventor's AndroidX lacks. Add `-dontwarn androidx.annotation.**` to
`src/proguard-rules.pro`; Rush names that rule in its help.

## In App Inventor

**The app build fails with `defined multiple times`.** Two extensions contain the same
class. This happens with extensions built by Rush 1, by Rush 2.0 for libraries it didn't
place as private, or by other tools, which shipped libraries without renaming them, and with libraries placed as `shared`. Rebuild
them with this Rush, or remove one. If only apps that also use a built-in component
fail, a shared library of the extension is one App Inventor adds for that component. See
[How libraries are shipped](dependencies.md#how-libraries-are-shipped).

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
`Screen.Initialize` runs, and posting them to the main looper doesn't reliably delay them
long enough. Fire them from [`onInitialize()`](writing-extensions.md#events) instead.
