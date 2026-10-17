# rush.yml

`rush.yml` configures a project. It's also described by a [JSON schema](../schema/rush.yml).
Unknown keys are an error.

```yaml
version: '1.2.0'
min_sdk: 21
homepage: https://github.com/example/counter
license: LICENSE.txt

assets:
- greeting.txt

dependencies:
- com.google.code.gson:gson:2.13.1
- my-library.aar

libraries:
  com.google.errorprone:error_prone_annotations: exclude

repositories:
- https://jitpack.io

kotlin:
  compiler_version: '2.4.20'
```

## version

**Required.** The extension's version name, shown in App Inventor. Use
`major.minor.patch`, quoted: Rush also derives App Inventor's numeric version from it.

## min_sdk

The minimum Android API level the extension supports. Defaults to 7. Code is desugared
for this level, and 24 or higher enables
[core library desugaring](building.md#java-and-kotlin-versions). `rush create` sets 21.

## homepage

A link to the extension's documentation, forum thread or repository. App Inventor links
to it from the component's help popup.

## license

The extension's license: a file in the project, which is packaged with the extension, or
a URL.

## assets

Files from the `assets` directory to package with the extension. See
[Assets](writing-extensions.md#assets).

## dependencies

Libraries the extension uses, as Maven coordinates (`group:artifact:version`) or file
names in the `deps` directory. See [Dependencies](dependencies.md).

## libraries

Where a library goes: `private` (the default), `shared`, `provided` or `exclude`, keyed
by `group:artifact` or by file name in `deps`. See
[Placing libraries](dependencies.md#placing-libraries).

## repositories

Maven repositories to search besides Maven Central and Google's Maven repository.

## kotlin

Kotlin compiler settings. `compiler_version` is the Kotlin compiler version, 2.4.20 by
default.

## Ignored keys

`authors` and `desugar` are accepted for compatibility with older projects, but have no
effect and make `rush build` warn. Code is always desugared.

## Deprecated keys

`provided_dependencies` lists libraries to compile against without shipping them. It
still works, with a warning, as if each entry were in `dependencies` and placed as
`provided` under `libraries`. `rush migrate` converts it.
