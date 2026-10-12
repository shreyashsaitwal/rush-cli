# Roadmap

Rush targets the latest MIT App Inventor release (currently **v206**). This file tracks
what is supported, what is planned and what is deliberately out of scope.

## Supported

| Feature | Since |
|---|---|
| Kotlin (1.8–2.4) and Java sources, mixed in one project | 2.0.0 |
| Java 8 language features desugared automatically | 2.0.0 |
| Java 17 language features (records, sealed classes, switch expressions, text blocks) | 2.2.0 |
| Core library desugaring (`java.time` and other Java APIs) for `min_sdk` 24 and higher | 2.2.0 |
| Android resources in `res/`, shipped in an AAR with names prefixed by the extension package | 2.2.0 |
| Maven dependencies from Maven Central and Google's Maven repository | 2.0.0 |
| Local JAR and AAR dependencies in `deps/` | 2.0.0 |
| AARs shipped with their resources, compiled by App Inventor | 2.0.0 |
| `AndroidManifest.xml`, merged with the manifests of AAR dependencies | 2.0.0 |
| Shrinking, optimization and obfuscation with ProGuard (`--optimize`) | 2.0.0 |
| Several extensions in one app, with shared libraries shipped as AARs | 2.1.0 |
| Private libraries relocated under the extension's package | 2.1.0 |
| Private libraries shrunk in every build | 2.1.0 |
| ProGuard rules from AARs and from `META-INF/proguard/` in jars | 2.1.0 |
| Blocks for continuations, dropdown options on getters, option descriptions from Javadoc | 2.1.0 |
| Property categories, license and icon handling matching App Inventor | 2.1.0 |
| Manifest permission constraints, features and escaped attributes | 2.1.0 |
| `rush upgrade` installs new releases | 2.1.0 |
| `rush migrate` for Rush 1 projects | 2.1.0 |
| Markdown documentation of the extension's blocks, written next to the AIX | 2.2.0 |
| GitHub Actions: a setup action and a build and release workflow in new projects | 2.2.0 |
| Instructions for AI coding agents in every project (`AGENTS.md`, a Claude skill, `rush agents`) | 2.3.0 |
| A dev container (Codespaces, VS Code) and setup for GitHub Copilot's cloud agent in every project | Unreleased |

## Not planned

| Feature | Reason |
|---|---|
| R8 as an alternative to ProGuard | ProGuard covers shrinking and obfuscation |
| Project-specific JDK in `rush.yml` | `JAVA_HOME` selects the JDK without committing a machine-specific path |
| Default build arguments | `rush build` has a single flag |
| Block images | Needs a Blockly renderer for little benefit |
| Shorter annotation names | App Inventor's own annotations keep sources portable |
| Stripping annotations from the AIX | App Inventor's components ship them too; the savings are negligible |
| Other JVM languages, Jetifier, AIDL, string obfuscation | Rarely needed |
| Core library desugaring below `min_sdk` 24 | The backport adds `java.util.function` classes that can't be relocated, so two extensions would clash |
| Several packages in one project | Packages would share one dependency set but each ship their own copy; separate projects stay clean, and one package can hold several components |
| Referencing AppCompat and AndroidX resources from extension resources | Rush would need to bundle and link App Inventor's whole AndroidX resource set |
| AI Companion support for AAR extensions | The Companion can't load AAR classes or resources |
