package io.github.shreyashsaitwal.rush.model

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class RushYaml(
    val version: String,
    val license: String = "",
    val homepage: String = "",
    val desugar: Boolean = false,
    @SerialName("min_sdk") val minSdk: Int = 7,

    val assets: List<String> = listOf(),
    val authors: List<String> = listOf(),
    val repositories: List<String> = listOf(),

    val kotlin: Kotlin = Kotlin(),

    @SerialName("dependencies") val runtimeDeps: List<String> = listOf(),
    // TODO @SerialName("comptime_dependencies") val compileDeps: List<String> = listOf(),
)

@Serializable
data class Kotlin(
    @SerialName("compiler_version") val compilerVersion: String? = null,
)
