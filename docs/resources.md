# Resources

Extensions can ship Android resources (layouts, drawables, strings, colors, dimensions,
styles…) from a `res` directory next to `src`, laid out as in any Android project:

```
counter/
├── res/
│   ├── layout/
│   │   └── com_example_counter_card.xml
│   ├── drawable/
│   │   └── com_example_counter_background.xml
│   └── values/
│       ├── colors.xml
│       └── strings.xml
└── src/
```

Rush generates an `R` class in the extension's package to use them:

```java
View card = LayoutInflater.from(form).inflate(R.layout.com_example_counter_card, null);
TextView title = card.findViewById(R.id.title);
title.setText(R.string.com_example_counter_title);
```

## Naming

Every resource name except IDs must start with the extension's package, with dots
replaced by underscores: `com_example_counter_` for `com.example.counter`. All the
resources of an app share one namespace, so without the prefix, two extensions (or an
extension and App Inventor) defining the same name would silently get one another's
values. A wrong name fails the build:

```
error string/title must be named com_example_counter_title
help  Resource names start with the extension package so they never clash with other extensions or App Inventor
```

IDs (`@+id/title`) don't need the prefix: sharing them is harmless.

`src/AndroidManifest.xml` must declare the extension's package
(`package="com.example.counter"`), which is the package of the `R` class.

## Validation

Rush compiles the resources with Android's `aapt2` on every build, so mistakes fail with
the file and line, like in Android Studio, instead of on App Inventor's build server.
`aapt2` (about 8 MB) is only downloaded for projects that have a `res` directory.

## References

Resources can reference each other and Android's own resources:

```xml
<TextView
    android:id="@+id/title"
    android:layout_width="wrap_content"
    android:layout_height="wrap_content"
    android:text="@string/com_example_counter_title"
    android:textColor="@color/com_example_counter_accent"
    android:background="?android:attr/selectableItemBackground"/>
```

They can also use the resources and views of the extension's dependencies, provided
ones included, such as
Media3's `@drawable/exo_icon_play`, a style whose parent is a library's style, or
`<androidx.media3.ui.PlayerView>`. When the library is private, Rush renames these
references in the shipped resources along with the library, and keeps the views when it
shrinks the code. The extension's `R` class lists only its own resources: use a
library's resources from code through the library's `R` class.

They can't reference App Inventor's AndroidX resources (`?attr/colorAccent`,
`@style/Theme.AppCompat`), which aren't available when Rush compiles them.

## How resources are shipped

The resources are shipped in an AAR inside the AIX, `aars/com.example.counter.aar`.
App Inventor compiles it with the app and generates the real `R` class; the one Rush
generates is only used to compile the extension.

Like any extension that ships AARs, extensions with resources work in built apps but not
in the AI Companion.
