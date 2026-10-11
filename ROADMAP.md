# Roadmap

Rush targets the latest MIT App Inventor release (currently **v206**). This file tracks
what is supported, what is planned and what is deliberately out of scope.

## Supported

| Feature | Since |
|---|---|
| Kotlin (1.8–2.4) and Java sources, mixed in one project | 2.0.0 |
| Java 8 language features desugared automatically | 2.0.0 |
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
| Markdown documentation of the extension's blocks, written next to the AIX | Unreleased |

## Planned

| Feature | Status |
|---|---|
| Extension-owned resources and custom XML layouts, shipped in an AAR Rush builds | Design |
| Java 9+ language features and core library desugaring (`java.time` and others) | Not started |
| Project-specific JDK and default build arguments in `rush.yml` | Not started |
| Several packages in one project, built as separate extensions in one AIX | Not started |

## Not planned

| Feature | Reason |
|---|---|
| R8 as an alternative to ProGuard | ProGuard covers shrinking and obfuscation |
| Block images | Needs a Blockly renderer for little benefit |
| Shorter annotation names | App Inventor's own annotations keep sources portable |
| Stripping annotations from the AIX | App Inventor's components ship them too; the savings are negligible |
| Other JVM languages, Jetifier, AIDL, string obfuscation | Rarely needed |
| AI Companion support for AAR extensions | The Companion can't load AAR classes or resources |
