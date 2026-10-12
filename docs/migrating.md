# Migrating from Rush 1

Rush 2 can't build Rush 1 projects as they are: `rush.yml` has a new format, and
extensions are declared with `@Extension` instead of `@DesignerComponent` and
`@SimpleObject`. `rush migrate` converts a project in place, so commit or back it up
first:

```sh
cd my-old-extension
rush migrate
```

## What it converts

- **`rush.yml`**: `version.name` becomes `version` (or `version.number` without a name,
  or `1.0.0` when the number was `auto`); `deps` becomes `dependencies`;
  `assets.other` becomes `assets`; `min_sdk`, `homepage`, `license` and `authors` are
  kept. JARs in `deps` that weren't listed in `deps` become `provided_dependencies`, as
  they were compile-only in Rush 1. Kotlin projects get `kotlin.compiler_version` and the
  Kotlin standard library as a dependency.
- **The extension class**: the source file named after the project's `name` gets an
  `@Extension` annotation with the old description and icon.

It then syncs the dependencies.

## What to do by hand

- **Permissions and manifest entries.** `@UsesPermissions`, `@UsesActivities`,
  `@UsesServices` and the other `@Uses…` annotations still compile but are ignored. Move
  what they declare to [`src/AndroidManifest.xml`](manifest.md).
- **Rush 1 annotations.** `@DesignerComponent` and `@SimpleObject` are ignored too; remove
  them once `@Extension` is in place.
- **Other extension classes.** Only the class named after the project gets `@Extension`.
  Annotate any others, and keep them all in one package.
- **Optimization.** `release.optimize` isn't migrated: pass `--optimize` to `rush build`.
- **Dropdowns.** Enums used as dropdowns must be in a directory named `helpers`. See
  [Dropdowns](writing-extensions.md#dropdowns).

Then build, and check the result in App Inventor:

```sh
rush build
```
