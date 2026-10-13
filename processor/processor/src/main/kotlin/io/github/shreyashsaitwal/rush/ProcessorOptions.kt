package io.github.shreyashsaitwal.rush

import org.json.JSONObject
import java.nio.file.Path
import java.nio.file.Paths

class ProcessorOptions(options: Map<String, String>) {
    private val file: Path = Paths.get(
        options[OPTIONS]
            ?: throw ProcessingError("Missing annotation processor option -A$OPTIONS. Build extensions with `rush build`.")
    )
    private val json = JSONObject(file.toFile().readText())

    val config: Path = path("config")
    val manifest: Path = path("manifest")
    val output: Path = path("output")
    val project: Path = path("project")
    val helperClasspath: List<Path> = require("helperClasspath") { json.getJSONArray(it).map { Paths.get(it.toString()) } }
    val version: String = require("version") { json.getString(it) }

    private fun path(key: String) = require(key) { Paths.get(json.getString(it)) }

    private fun <T> require(key: String, read: (String) -> T): T {
        if (!json.has(key)) {
            throw ProcessingError("$key is missing from the processor options in $file")
        }
        return read(key)
    }

    companion object {
        const val OPTIONS = "rush.options"
    }
}
