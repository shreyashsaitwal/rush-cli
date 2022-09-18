package io.shreyash.rush.processor.model

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class RushYaml(
    val version: String,
    val license: String = "",
    val homepage: String = "",
    val desugar: Boolean = false,
    val assets: List<String> = listOf(),
    val authors: List<String> = listOf(),
    @SerialName("dependencies") val runtimeDeps: List<String> = listOf(),
    @SerialName("comptime_dependencies") val compileDeps: List<String> = listOf(),
    val android: Android = Android(),
    val kotlin: Kotlin = Kotlin(),
)

@Serializable
data class Android(
    @SerialName("compile_sdk") val compileSdk: Int = 31,
    @SerialName("min_sdk") val minSdk: Int = 7,
)

@Serializable
data class Kotlin(
    @SerialName("compiler_version") val compilerVersion: String = "1.7.10",
)
