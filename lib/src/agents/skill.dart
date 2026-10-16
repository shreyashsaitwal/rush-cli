import 'package:rush/src/version.dart';

String get rushSkill => _skill.replaceAll('{version}', packageVersion);

const _skill = r'''---
name: rush
description: Writes, builds and checks MIT App Inventor extensions with the Rush CLI. Use when creating or changing extension code, blocks, rush.yml, dependencies, Android resources or the manifest of this project.
---

# Building App Inventor extensions with Rush

This project is an MIT App Inventor extension built with Rush {version}. Rush compiles the Java or Kotlin sources in `src/` into an `.aix` file that people import into App Inventor.

## Workflow

1. Change the code.
2. Run `rush build`. Fix every error before continuing. Errors name the file and line, or the exact fix.
3. Read `out/<package>.md`. It lists the blocks App Inventor will show: names, parameters, types and descriptions. Check that they match what was asked.
4. Report what can't be checked without App Inventor: what the blocks do at runtime. Tell the user how to test it. Extensions that ship AARs (see Dependencies and Resources) must be tested in a built app, because the AI Companion can't load AARs.

Never edit `.rush/` or `out/`: Rush generates them. `rush clean` deletes `.rush/` when a build behaves strangely.

## Project layout

| Path | Contents |
|---|---|
| `rush.yml` | Version, `min_sdk`, dependencies, assets |
| `src/` | Java and Kotlin sources, in the extension's package |
| `src/AndroidManifest.xml` | Permissions, services, activities and other manifest entries |
| `src/proguard-rules.pro` | Rules for `rush build --optimize` |
| `assets/` | The icon and files the extension ships |
| `deps/` | Local JAR and AAR libraries |
| `res/` | Android resources (optional) |

## The extension class

```java
package com.example.counter;

import com.google.appinventor.components.annotations.Extension;
import com.google.appinventor.components.runtime.AndroidNonvisibleComponent;
import com.google.appinventor.components.runtime.ComponentContainer;

/** Counts things, up or down. */
@Extension(icon = "icon.png")
public class Counter extends AndroidNonvisibleComponent {
  public Counter(ComponentContainer container) {
    super(container.$form());
  }
}
```

- Extensions are always non-visible components: App Inventor's designer lists them below the screen and can't place or size them. Extend `AndroidNonvisibleComponent`, never `AndroidViewComponent`. To show a view, see Showing views.
- `@Extension` takes a `description` (Markdown; the class Javadoc when empty) and an `icon` (a file in `assets/` or a URL).
- `form`, inherited from `AndroidNonvisibleComponent`, is the screen. It's an `Activity`: use it as the Android `Context`.
- Several `@Extension` classes in one project become several components in one AIX. They must all be in the same package.
- Only methods declared directly in an `@Extension` class become blocks.
- In Kotlin, escape `$form`: ``AndroidNonvisibleComponent(container.`$form`())``.

## Showing views

Take an arrangement the user placed on the screen as a block parameter, and add the view to it. The arrangement's Width, Height and Visible then control the view.

```java
@SimpleFunction(description = "Shows the count inside an arrangement, filling it.")
public void ShowIn(AndroidViewComponent arrangement) {
  if (!(arrangement.getView() instanceof ViewGroup)) {
    form.dispatchErrorOccurredEvent(this, "ShowIn", ErrorMessages.ERROR_EXTENSION_ERROR,
        1, "Counter", "ShowIn needs a HorizontalArrangement or VerticalArrangement.");
    return;
  }
  if (display.getParent() != null) {
    ((ViewGroup) display.getParent()).removeView(display);
  }
  ((ViewGroup) arrangement.getView()).addView(display, new ViewGroup.LayoutParams(
      ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT));
}
```

Create the view in the constructor, with `form` as its `Context`.

## Blocks

Blocks are public methods with a block annotation. Names are `PascalCase`, parameters `camelCase`. Every block takes a `description`; without one, the Javadoc is used.

### Functions

```java
@SimpleFunction(description = "Returns the sum of a list of numbers.")
public double Sum(YailList numbers) {
  double sum = 0;
  for (Object number : numbers.toArray()) {
    sum += Double.parseDouble(number.toString());
  }
  return sum;
}
```

### Properties

A getter (no parameters) and a setter (one parameter) with the same name. A getter alone is read-only; a setter alone is write-only.

```java
@SimpleProperty(description = "How much each step changes the count.")
public int Step() {
  return step;
}

@DesignerProperty(editorType = PropertyTypeConstants.PROPERTY_TYPE_NON_NEGATIVE_INTEGER, defaultValue = "1")
@SimpleProperty
public void Step(int step) {
  this.step = step;
}
```

- `@DesignerProperty` on the setter shows the property in the designer. App Inventor calls the setter at startup with the designer value or `defaultValue`. The setter also needs `@SimpleProperty`.
- Editor types (`PropertyTypeConstants`): `PROPERTY_TYPE_STRING`, `PROPERTY_TYPE_TEXTAREA`, `PROPERTY_TYPE_BOOLEAN`, `PROPERTY_TYPE_INTEGER`, `PROPERTY_TYPE_NON_NEGATIVE_INTEGER`, `PROPERTY_TYPE_FLOAT`, `PROPERTY_TYPE_NON_NEGATIVE_FLOAT`, `PROPERTY_TYPE_COLOR`, `PROPERTY_TYPE_ASSET`, and `PROPERTY_TYPE_CHOICES` with the values in `editorArgs`.
- `@SimpleProperty(category = PropertyCategory.BEHAVIOR)` groups the property; `userVisible = false` hides its blocks.

### Events

```java
@SimpleEvent(description = "The count reached a multiple of ten.")
public void Milestone(int count) {
  EventDispatcher.dispatchEvent(this, "Milestone", count);
}
```

- Call the event method from your code. The name passed to `dispatchEvent` must equal the method name, and the arguments must match its parameters.
- Fire events on the main thread. From other threads, post them: `form.runOnUiThread(() -> Milestone(count));`.
- App Inventor drops events fired while `Screen.Initialize` runs, which includes designer property setters. Fire startup events from `onInitialize()`: implement `OnInitializeListener` (package `com.google.appinventor.components.runtime.util`) and call `form.registerForOnInitialize(this)` in the constructor. App Inventor calls it once `Screen.Initialize` has finished.

### Types

| Java or Kotlin | Block type |
|---|---|
| `int`, `long`, `short`, `byte`, `float`, `double` | number |
| `boolean` | boolean |
| `String` | text |
| `YailList`, `java.util.List` | list |
| `YailDictionary` | dictionary |
| `java.util.Calendar` | instant in time |
| `Object` | any |
| `Component` and its subclasses | component |
| a dropdown enum | that dropdown |

Use primitives: `Integer`, `Boolean` and Kotlin's `Int?` fail the build. Arrays, `char`, maps and your own classes aren't block types.

### Slow work

App Inventor doesn't wait for results delivered later. Run slow work on another thread and deliver the result through an event:

```java
@SimpleFunction(description = "Counts the bytes of an asset without blocking the app.")
public void CountAssetSize(@Asset String asset) {
  new Thread(() -> {
    int size = 0;
    try (InputStream in = form.openAsset(asset)) {
      while (in.read() != -1) {
        size++;
      }
    } catch (IOException e) {
      size = -1;
    }
    int result = size;
    form.runOnUiThread(() -> AssetSizeCounted(asset, result));
  }).start();
}

@SimpleEvent(description = "An asset's bytes were counted. The size is -1 if it can't be read.")
public void AssetSizeCounted(String asset, int size) {
  EventDispatcher.dispatchEvent(this, "AssetSizeCounted", asset, size);
}
```

Don't use `Continuation<T>` for slow work: App Inventor reads its result as soon as the function returns, so a result passed later is lost and the block returns `false`. Rush warns about it.

### Dropdowns

An enum implementing `OptionList`, in a directory named `helpers` (for example `src/com/example/counter/helpers/Direction.java`). Elsewhere the build fails. Each constant's Javadoc becomes its description; `@Default` marks the default.

```java
package com.example.counter.helpers;

import com.google.appinventor.components.common.Default;
import com.google.appinventor.components.common.OptionList;

public enum Direction implements OptionList<String> {
  /** Counts upwards. */
  @Default
  Up("up"),
  /** Counts downwards. */
  Down("down");

  private final String value;

  Direction(String value) {
    this.value = value;
  }

  public String toUnderlyingValue() {
    return value;
  }
}
```

Use the enum as a parameter or return type, or keep the underlying type and add `@Options(Direction.class)` to the parameter or getter.

### Assets

- `@Asset String file` gives a parameter a dropdown of the app's media files. Open them with `form.openAsset(file)`.
- Files the extension ships go in `assets/` and are listed under `assets:` in `rush.yml`. Open them with `form.openAssetForExtension(this, "data.json")`.

### Designing blocks

App Inventor is for beginners. Give each block a distinct name (overloads become duplicate blocks), give properties sensible defaults, prefer simple units (milliseconds), start list positions at 1, and never block the main thread: deliver slow results through an event or an asynchronous function. Put a property's description on its getter or its setter, not both.

### Deprecated blocks

`@Deprecated` keeps a block working in existing apps but hides it from the docs.

## Lifecycle and errors

Extensions holding players, sensors or connections follow the screen's lifecycle. Implement `OnPauseListener`, `OnResumeListener`, `OnStopListener` or `OnDestroyListener` and register in the constructor with `form.registerForOnPause(this)` (and `OnResume`, `OnStop`, `OnDestroy`). `onResume()` may also run when the screen first starts.

Report errors through the screen's `ErrorOccurred` event:

```java
form.dispatchErrorOccurredEvent(this, "ShowIn", ErrorMessages.ERROR_EXTENSION_ERROR,
    1, "Counter", "ShowIn needs a HorizontalArrangement or VerticalArrangement.");
```

The arguments after `ERROR_EXTENSION_ERROR` (error 3300) are your error code, the extension's name and the message. Without an `ErrorOccurred` handler App Inventor shows an alert. Errors reported while `Screen.Initialize` runs are lost.

## Manifest and permissions

Declare everything the app needs in `src/AndroidManifest.xml`: `<uses-permission>`, `<uses-feature>`, `<queries>`, and `<application>` children (`<service>`, `<activity>`, `<receiver>`, `<provider>`, `<meta-data>`). Other tags, such as `<uses-sdk>`, are ignored. `${applicationId}` becomes the app's package name. Rush 1's `@UsesPermissions` and similar annotations have no effect.

Request dangerous permissions at runtime:

```java
form.askPermission(Manifest.permission.CAMERA, (permission, granted) -> {
  if (granted) {
    startCamera();
  }
});
```

Throw `new PermissionException(permission)` from a block that needs a denied permission; App Inventor then fires the screen's `PermissionDenied` event.

## Dependencies

```yaml
dependencies:
- com.google.code.gson:gson:2.13.1   # Maven: group:artifact:version
- my-library.jar                     # a file in deps/
libraries:                           # overrides where a library goes
  com.example:unwanted: exclude      # never resolved, nor what only it needs
  my-library.jar: provided           # compiled against, never shipped
repositories:
- https://jitpack.io                 # besides Maven Central and Google
```

- Declare every library the code uses. Guava, Gson and RecyclerView compile without being declared, but App Inventor only includes them in some apps; undeclared, they fail at runtime with `NoClassDefFoundError`.
- App Inventor always provides its runtime, Kawa and 2018-era AndroidX (appcompat 1.0.0, core 1.9.0, fragment 1.0.0, lifecycle 2.0.0…). These versions always win. Rush warns when a dependency needs a newer one; such libraries may fail at runtime. Jetpack Compose can't work. Missing `androidx.annotation` classes are compile-time only: `-dontwarn androidx.annotation.**`.
- Libraries are private by default: Rush renames them into the extension's package (code, and AARs' resources, manifests and file names), so copies in other extensions, App Inventor or Kodular can't clash. Intent actions and categories keep their value. Extensions that ship AARs don't work in the AI Companion.
- Kotlin projects need `org.jetbrains.kotlin:kotlin-stdlib:<version>` in `dependencies` and the compiler version in `kotlin.compiler_version`.
- `rush deps tree` shows what was resolved, where each library goes and why. `libraries` places a library (`group:artifact` or file name) as `shared` (shipped unchanged as an AAR, for objects that pass between extensions), `provided` or `exclude`; unplaced libraries are `private`. AARs with assets, native code or JARs in `libs/` can't be private: the build error names the `shared` entry to add.

## Resources

Layouts, drawables, strings and colors go in `res/`, laid out as in Android. Use them through the `R` class of the extension's package: `R.layout.com_example_counter_card`.

- Every name except IDs starts with the package, dots replaced by underscores: `com_example_counter_title` in `com.example.counter`.
- `src/AndroidManifest.xml` must declare `package="<extension package>"`.
- References to Android's own resources work (`@android:color/white`, `?android:attr/selectableItemBackground`), and so do those of the extension's dependencies (`@drawable/exo_icon_play`, a library style as parent); Rush renames them with private libraries. App Inventor's AppCompat and AndroidX resources (`?attr/colorAccent`) don't.
- The extension's `R` class has only its own resources; reach a library's through that library's `R` class.

## Java, Kotlin and Android versions

- Java 17 language features work on every Android version: records, switch expressions, text blocks, `var`.
- Java APIs must exist on the device for `min_sdk` in `rush.yml`. With `min_sdk` 24 or higher, `java.time` and other APIs added after Android 7 work too.

## Optimizing

`rush build --optimize` shrinks and obfuscates with R8 (in ProGuard compatibility mode) and writes `out/<package>.mapping.txt`. Rush moves optimized classes under `<package>.repacked` itself, so never set `-repackageclasses`. A `Missing class` error means shipped code uses a class nothing ships: add its library to `dependencies`, or `-dontwarn` it if that code never runs. Add `-keep` rules to `src/proguard-rules.pro` for classes reached by reflection.

## Fixing common errors

| Error | Fix |
|---|---|
| `No extension found` | Annotate the extension class with `@Extension` |
| `Found use of boxed type java.lang.Integer` | Use `int` |
| `Cannot convert Java type '…' to YAIL type` | Use a block type from the table above |
| `Dropdown enum … must be in a directory named helpers` | Move the enum into a `helpers` directory |
| `string/x must be named com_example_counter_x` | Prefix the resource name with the package |
| `… is listed in rush.yml but doesn't exist` | Add the file, or remove it from `rush.yml` |
| `… is required, but App Inventor provides an older version` | Prefer an older version of the dependency, and test the features used |
| `Could not run javac` | Install JDK 17 or newer |

## Reference

The full documentation for this Rush version: https://github.com/shreyashsaitwal/rush-cli/tree/v{version}/docs

App Inventor's guides for component authors: https://ai2.appinventor.mit.edu/reference/other/extensions.html and How to Add a Component (https://docs.google.com/document/d/1xk9dMfczvjbbwD-wMsr-ffqkTlE3ga0ocCE1KOb2wvw/edit). Rush replaces their build steps.
''';
