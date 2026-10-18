# Roadmap

Rush targets the latest MIT App Inventor release (currently **v206**). This file tracks
what is supported, what is planned and what is deliberately out of scope.

## Supported

| Feature | Since |
|---|---|
| Kotlin (1.8–2.4) and Java sources, mixed in one project | 2.0.0 |
| Java 8 language features desugared automatically | 2.0.0 |
| Java 17 language features (records, sealed classes, switch expressions, text blocks) | 2.0.0 |
| Core library desugaring (`java.time` and other Java APIs) for `min_sdk` 24 and higher | 2.0.0 |
| Android resources in `res/`, shipped in an AAR with names prefixed by the extension package | 2.0.0 |
| Maven dependencies from Maven Central and Google's Maven repository | 2.0.0 |
| Local JAR and AAR dependencies in `deps/` | 2.0.0 |
| AARs shipped with their resources, compiled by App Inventor | 2.0.0 |
| `AndroidManifest.xml`, merged with the manifests of AAR dependencies | 2.0.0 |
| `${applicationId}` in library manifests becomes the app's package | 2.0.0 |
| AAR ids written in the form App Inventor's aapt accepts | 2.0.0 |
| Shrinking, optimization and obfuscation with R8 (`--optimize`), with a mapping file | 2.0.0 |
| Several extensions in one app, with shared libraries shipped as AARs | 2.0.0 |
| Private libraries relocated under the extension's package | 2.0.0 |
| `libraries` in `rush.yml` places a library: `exclude`, `provided`, `shared` or `private`; `rush deps tree` shows where each goes and why | 2.0.0 |
| Libraries App Inventor adds only for some components are bundled, never assumed present | 2.0.0 |
| Private libraries shrunk in every build | 2.0.0 |
| ProGuard rules from AARs and from `META-INF/proguard/` in jars | 2.0.0 |
| Blocks for continuations, dropdown options on getters, option descriptions from Javadoc | 2.0.0 |
| A warning for continuation results App Inventor doesn't wait for | 2.0.0 |
| Property categories, license and icon handling matching App Inventor | 2.0.0 |
| Manifest permission constraints, features and escaped attributes | 2.0.0 |
| `rush upgrade` installs new releases | 2.0.0 |
| `rush migrate` for Rush 1 projects and `provided_dependencies` | 2.0.0 |
| Markdown documentation of the extension's blocks, written next to the AIX | 2.0.0 |
| GitHub Actions: a setup action and a build and release workflow in new projects | 2.0.0 |
| Instructions for AI coding agents in every project (`AGENTS.md`, a Claude skill, `rush agents`) | 2.0.0 |
| A dev container (Codespaces, VS Code) and setup for GitHub Copilot's cloud agent in every project | 2.0.0 |
| Byte-reproducible AIX output: two clean builds of a project produce identical files | 2.0.0 |
| AARs with font resources build on Kodular (fonts moved to `res/raw`, `R.font` kept working) | 2.0.0 |
| Unchanged compile and DEX steps skipped; desugared libraries cached once for all projects | 2.0.0 |
| A template repository that creates a project in the browser | 2.0.0 |
| Every library private by default: AARs renamed with their resources, manifest and file name, so extensions don't clash with each other or with App Inventor's and Kodular's libraries | 2.1.0 |
| `shared` as the explicit choice for libraries whose objects pass between extensions | 2.1.0 |
| `original_names` keeps packages' names; AARs with native libraries can be private, and Rush names the packages their native code needs | 2.1.0 |
| The extension and its private libraries shrunk by R8 as one program | 2.1.0 |
| Extension resources referencing their libraries' resources and App Inventor's AndroidX (`Theme.AppCompat`) | 2.1.0 |
| Kotlin Multiplatform libraries: AARs without code, and `-jvm` and `-android` artifacts of libraries App Inventor provides | 2.1.0 |
| Extensions built for different `min_sdk` in one app (D8's desugared interface fields corrected) | 2.1.0 |
| Prereleases installable by version (`RUSH_VERSION`, the setup action's `version`) | 2.1.0 |

## Not planned

| Feature | Reason |
|---|---|
| Project-specific JDK in `rush.yml` | `JAVA_HOME` selects the JDK without committing a machine-specific path |
| Default build arguments | `rush build` has a single flag |
| Block images | Needs a Blockly renderer for little benefit |
| Shorter annotation names | App Inventor's own annotations keep sources portable |
| Stripping annotations from the AIX | App Inventor's components ship them too; the savings are negligible |
| Other JVM languages, Jetifier, AIDL, string obfuscation | Rarely needed |
| Core library desugaring below `min_sdk` 24 | The backport adds `java.util.function` classes that can't be relocated, so two extensions would clash |
| Several packages in one project | Packages would share one dependency set but each ship their own copy; separate projects stay clean, and one package can hold several components |
| AI Companion support for AAR extensions | The Companion can't load AAR classes or resources |
