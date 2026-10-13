# Writing extensions

An extension is a class annotated with `@Extension` that extends
`AndroidNonvisibleComponent`. Its public methods become blocks when they carry one of
the block annotations below. The examples on this page come from one extension, a
counter, which builds as shown.

App Inventor's own guides cover the same ground for its built-in components:
[App Inventor extensions](https://ai2.appinventor.mit.edu/reference/other/extensions.html)
and [How to Add a Component](https://docs.google.com/document/d/1xk9dMfczvjbbwD-wMsr-ffqkTlE3ga0ocCE1KOb2wvw/edit).
Rush replaces their build steps (building App Inventor from source, `ant extensions`), but
their advice on designing components applies as is.

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

`form` (inherited from `AndroidNonvisibleComponent`) is the screen the component is on.
It's an Android `Activity`, so it serves as the `Context` for Android APIs.

**`@Extension`** takes:

- `description`: the text of the component's help popup in App Inventor. Markdown is
  supported, including links. When it's empty, the class's Javadoc is used, as above.
- `icon`: a file in the `assets` directory, or an `http(s)` URL. Without one, the
  extension gets App Inventor's default extension icon.

A project can contain several extensions, which all share one AIX. They must be in the
same package, and only methods declared directly in an extension class become blocks.

In Kotlin, `$form` must be escaped:

```kotlin
@Extension(icon = "icon.png")
class Counter(container: ComponentContainer) : AndroidNonvisibleComponent(container.`$form`()) {
}
```

## Showing views

App Inventor shows every extension as a non-visible component: the designer lists it
below the screen and can't place or size it. An extension can still show views in the
app. Let the user place an arrangement where the view should go, and take it as a block
parameter:

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

`display` is a `TextView` the constructor creates with `new TextView(form)`. The
arrangement's Width, Height and Visible properties then size and show the view, and
HorizontalArrangement and VerticalArrangement both work.

Don't extend `AndroidViewComponent` instead: such an extension builds, but App Inventor
can't place it on the screen, and its inherited Width and Height have no blocks.

## Functions

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

Every block annotation takes a `description`. When it's missing, the method's Javadoc is
used, and Rush warns if there's neither. Block names should be `PascalCase` and parameter
names `camelCase`, as in App Inventor's own components. Rush warns otherwise.

## Block types

Parameters and return values must be one of these types:

| Java or Kotlin type | Block type |
|---|---|
| `int`, `long`, `short`, `byte`, `float`, `double` | number |
| `boolean` | boolean |
| `String` | text |
| `YailList`, `java.util.List` | list |
| `YailDictionary` | dictionary |
| `java.util.Calendar` | instant in time |
| `Object` | any |
| App Inventor components (`Component` and its subclasses) | component |
| A [dropdown enum](#dropdowns) | that dropdown |

Use primitives: `Integer`, `Boolean` and Kotlin's nullable `Int?` fail the build with
`Found use of boxed type java.lang.Integer. Please use the primitive type int instead.`
Other types, such as arrays, `char` and your own classes, fail with
`Cannot convert Java type '…' to YAIL type.`

## Properties

A property is a getter, a setter, or both, with the same name:

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

A getter takes no parameters and a setter takes exactly one. A property with only a
getter is read-only in the blocks; one with only a setter is write-only.

`@SimpleProperty` also takes:

- `category`: the group the property is listed under, such as
  `PropertyCategory.BEHAVIOR` or `PropertyCategory.APPEARANCE`.
- `userVisible = false`: hides the property's blocks.

### Designer properties

`@DesignerProperty` on a setter also shows the property in the designer's Properties
panel. When the app starts, App Inventor calls the setter with the value set in the
designer, or `defaultValue`. The setter must also have `@SimpleProperty`.

`editorType` picks the editor, from `PropertyTypeConstants`. Common ones:

| Editor type | Edits |
|---|---|
| `PROPERTY_TYPE_STRING`, `PROPERTY_TYPE_TEXTAREA` | text |
| `PROPERTY_TYPE_BOOLEAN` | a checkbox |
| `PROPERTY_TYPE_INTEGER`, `PROPERTY_TYPE_NON_NEGATIVE_INTEGER` | whole numbers |
| `PROPERTY_TYPE_FLOAT`, `PROPERTY_TYPE_NON_NEGATIVE_FLOAT` | decimal numbers |
| `PROPERTY_TYPE_COLOR` | a color, as `&HAARRGGBB` |
| `PROPERTY_TYPE_ASSET` | one of the project's media files |
| `PROPERTY_TYPE_CHOICES` | one of the values listed in `editorArgs` |

`editorArgs` passes arguments to the editor, and `alwaysSend = true` calls the setter at
startup even when the value is the default.

## Events

An event is a method that fires the event block through `EventDispatcher`. Call it from
your code when the event happens:

```java
@SimpleFunction(description = "Moves the count one step in the current direction.")
public void Increment() {
  count += direction == Direction.Up ? step : -step;
  if (count % 10 == 0) {
    Milestone(count);
  }
}

@SimpleEvent(description = "The count reached a multiple of ten.")
public void Milestone(int count) {
  EventDispatcher.dispatchEvent(this, "Milestone", count);
}
```

The name passed to `dispatchEvent` must match the method name, and the arguments must
match its parameters.

Fire events on the main thread. Work done on another thread must be posted back, for
example with `form.runOnUiThread(…)` or a `Handler` on the main looper.

Events fired while `Screen.Initialize` runs are dropped, and that includes designer
property setters. To fire an event at startup, implement `OnInitializeListener` (from
`com.google.appinventor.components.runtime.util`). App Inventor calls `onInitialize()`
once `Screen.Initialize` has finished:

```java
public Counter(ComponentContainer container) {
  super(container.$form());
  form.registerForOnInitialize(this);
}

@Override
public void onInitialize() {
  Ready();
}
```

## Asynchronous functions

A function whose last parameter is a `Continuation<T>` becomes an asynchronous block: its
result is passed to the continuation, and the blocks after it wait for that result.
The function must return `void`.

```java
@SimpleFunction(description = "Counts the bytes of an asset without blocking the app.")
public void AssetSize(@Asset String asset, Continuation<Integer> callback) {
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
    handler.post(() -> callback.call(result));
  }).start();
}
```

`handler` is a `new Handler(Looper.getMainLooper())`, which runs code on the main thread.

`T` is the result type: one of the [block types](#block-types), with boxed types such as
`Integer` and `Boolean` instead of primitives, or `Void` for a block without a result
(call `callback.call(null)`). Call the continuation on the main thread, exactly once.

## The screen's lifecycle

Extensions that hold resources, such as players, sensors or connections, should follow
the screen's lifecycle. Implement the listener and register it in the constructor:

| Interface | Called when | Register with |
|---|---|---|
| `OnPauseListener` | another activity comes to the front, or the screen turns off | `form.registerForOnPause(this)` |
| `OnResumeListener` | the screen comes back | `form.registerForOnResume(this)` |
| `OnStopListener` | the screen is no longer visible | `form.registerForOnStop(this)` |
| `OnDestroyListener` | the screen is closing | `form.registerForOnDestroy(this)` |

```java
@Override
public void onPause() {
  paused = true;
}

@Override
public void onResume() {
  if (paused) {
    paused = false;
    Resumed();
  }
}
```

`onResume()` may also run when the screen first starts, before any pause, so the counter
only fires `Resumed` after one. A component that implements `Deleteable` gets `onDelete()`
when it's deleted while the app runs, which mostly happens in the AI Companion.

## Reporting errors

Report errors through the screen's `ErrorOccurred` event, the way App Inventor's own
components do:

```java
form.dispatchErrorOccurredEvent(this, "ShowIn", ErrorMessages.ERROR_EXTENSION_ERROR,
    1, "Counter", "ShowIn needs a HorizontalArrangement or VerticalArrangement.");
```

`ERROR_EXTENSION_ERROR` is error 3300, and its arguments are your own error code, the
extension's name and the message. `Screen.ErrorOccurred` receives the function name, 3300
and `Error 1 in extension Counter: ShowIn needs…`. Without an `ErrorOccurred` handler,
App Inventor shows the message in an alert. Errors reported while `Screen.Initialize`
runs are lost, like events.

## Designing blocks

App Inventor is made for beginners, and its guide for component authors asks for blocks
that follow these principles:

- **Each block name is used once.** App Inventor doesn't support overloading: give each
  function a distinct name.
- **Properties have sensible defaults,** so the extension works before the user changes
  anything.
- **Blocks do what their names say.** Choose the behavior that surprises a beginner least,
  and prefer simple units, such as milliseconds over fractions of a second.
- **Lists start at 1,** like App Inventor's own lists.
- **Slow work doesn't block the app.** Run it on another thread and deliver the result
  through an event or an [asynchronous function](#asynchronous-functions).
- **A property's description goes on its getter or its setter,** not both.

## Dropdowns

A dropdown is an enum that implements `OptionList`. Each constant's Javadoc becomes the
option's description, and `@Default` marks the default option (otherwise the first one):

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

Dropdown enums must be in a directory named `helpers`, like
`src/com/example/counter/helpers/`. Rush compiles them first, because it reads their
constants while compiling the extension.

Use the enum as a parameter or return type, or keep the underlying type and mark it with
`@Options`:

```java
@SimpleProperty(description = "Which way the count moves.")
public @Options(Direction.class) String Direction() {
  return direction.toUnderlyingValue();
}

@DesignerProperty(editorType = PropertyTypeConstants.PROPERTY_TYPE_CHOICES, defaultValue = "up", editorArgs = {"up", "down"})
@SimpleProperty
public void Direction(@Options(Direction.class) String direction) {
  this.direction = "down".equals(direction) ? Direction.Down : Direction.Up;
}
```

## Assets

`@Asset` on a `String` parameter gives the block a dropdown of the app's media files, as
in `AssetSize` above. Read them with `form.openAsset(name)`.

Files the extension itself needs go in the `assets` directory and must be listed in
`rush.yml`:

```yaml
assets:
- greeting.txt
```

They're packaged with the extension. Open them with
`form.openAssetForExtension(this, "greeting.txt")`.

## Deprecating blocks

`@Deprecated` keeps a block working in existing projects but marks it deprecated, and
leaves it out of the generated documentation:

```java
@Deprecated
@SimpleFunction
public void Reset() {
  count = 0;
}
```

## Permissions and other manifest entries

Rush 1's `@UsesPermissions`, `@UsesActivities` and similar annotations still compile but
have no effect. Declare permissions, activities and services in
[`src/AndroidManifest.xml`](manifest.md).
