package io.shreyash.rush.processor

import com.charleskorn.kaml.Yaml
import io.shreyash.rush.processor.model.Extension
import io.shreyash.rush.processor.model.RushYaml
import org.commonmark.ext.autolink.AutolinkExtension
import org.commonmark.ext.task.list.items.TaskListItemsExtension
import org.commonmark.parser.Parser
import org.commonmark.renderer.html.HtmlRenderer
import org.w3c.dom.*
import org.xml.sax.SAXException
import shaded.org.json.JSONArray
import shaded.org.json.JSONException
import shaded.org.json.JSONObject
import java.io.FileInputStream
import java.io.IOException
import java.nio.file.Paths
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.util.regex.Pattern
import javax.xml.parsers.DocumentBuilderFactory
import javax.xml.parsers.ParserConfigurationException
import kotlin.io.path.createDirectory
import kotlin.io.path.exists

class InfoFilesGenerator(
    private val extensions: List<Extension>,
) {
    private val projectRoot = System.getenv("RUSH_PROJECT_ROOT")
    private val rawBuildDir = Paths.get(projectRoot, ".rush", "build", "raw").apply {
        if (!this.exists()) this.createDirectory()
    }

    /**
     * Generates the components.json file.
     *
     * @throws IOException
     * @throws JSONException
     */
    fun generateComponentsJson() {
        val yaml = metadataFile()
        val componentsJsonArray = JSONArray()

        for (ext in extensions) {
            val extJsonObj = JSONObject()

            // These are always the same for all extensions.
            extJsonObj
                .put("external", "true")
                .put("categoryString", "EXTENSION")
                .put("showOnPalette", "true")
                .put("nonVisible", "true")

            extJsonObj
                .put("name", ext.extensionComponent.name)
                .put("helpString", parseMdString(ext.extensionComponent.description))
                .put("type", ext.fqcn)
                .put("helpUrl", yaml.homepage)
                .put("licenseName", yaml.license)
                .put("versionName", yaml.version)
                // Choosing version at random because it has no effect whatsoever.
                .put("version", (0..999_999).random().toString())
                .put("androidMinSdk", yaml.android.minSdk.coerceAtLeast(7))

            val urlPattern = Pattern.compile(
                """https?://(www\.)?[-a-zA-Z0-9@:%._+~#=]{1,256}\.[a-zA-Z0-9()]{1,6}\b([-a-zA-Z0-9()!@:%_+.~#?&//=]*)"""
            )
            val icon = ext.extensionComponent.icon
            if (urlPattern.matcher(icon).find()) {
                extJsonObj.put("iconName", icon)
            } else {
                val origIcon = Paths.get(projectRoot, "assets", icon).toFile()
                Paths.get(rawBuildDir.toString(), "aiwebres", icon).toFile().apply {
                    if (this.exists()) this.delete()
                    origIcon.copyTo(this)
                }
                extJsonObj.put("iconName", "aiwebres/$icon")
            }

            val time = LocalDate.now().format(DateTimeFormatter.ISO_DATE)
            extJsonObj.put("dateBuilt", time)

            // Put all blocks' descriptions
            extJsonObj
                .put("events", ext.events.map { it.asJsonObject() })
                .put("methods", ext.functions.map { it.asJsonObject() })
                .put("blockProperties", ext.properties.map { it.asJsonObject() })
                .put("properties", ext.designerProperties.map { it.asJsonObject() })

            componentsJsonArray.put(extJsonObj)
        }

        val componentsJsonFile = Paths.get(rawBuildDir.toString(), "components.json").toFile()
        componentsJsonFile.writeText(componentsJsonArray.toString())
    }

    /**
     * Generate component_build_infos.json file.
     *
     * @throws IOException
     * @throws ParserConfigurationException
     * @throws SAXException
     */
    fun generateBuildInfoJson() {
        val yaml = metadataFile()
        val buildInfoJsonArray = JSONArray()

        for (ext in extensions) {
            val extJsonObj = JSONObject()
                .put("type", ext.fqcn)
                .put("androidMinSdk", listOf(yaml.android.minSdk.coerceAtLeast(7)))

            // Put assets
            val assets = yaml.assets.map { it.trim() }
            extJsonObj.put("assets", assets)

            buildInfoJsonArray.put(extJsonObj)
        }

        // TODO: Add ability to declare extension specific manifest elements

        // Before the annotation processor runs, the CLI merges the manifests of all the AAR deps
        // with the extension's main manifest into a single manifest file.
        // So, if the merged manifest is found use it instead of the main manifest.
        val mergedManifest = Paths.get(rawBuildDir.toString(), "..", "files", "AndroidManifest.xml")
        val manifest = if (mergedManifest.exists()) {
            mergedManifest.toFile()
        } else {
            Paths.get(projectRoot, "src", "AndroidManifest.xml").toFile()
        }

        val builder = DocumentBuilderFactory.newInstance().newDocumentBuilder()
        val doc = builder.parse(manifest)

        // Put application elements
        val appElements = applicationElementsXmlString(doc)
        // We put all the elements under the activities tag. This lets us use the tags which aren't
        // yet added to AI2 and don't have a dedicated key in the build info JSON file.
        // The reason why this works is that AI compiler doesn't perform any checks on these
        // manifest arrays in the build info file, and just adds them to the final manifest file.
        buildInfoJsonArray.getJSONObject(0).put("activities", appElements)

        // Put permissions
        val nodes = doc.getElementsByTagName("uses-permission")
        val permissions = JSONArray()
        if (nodes.length != 0) {
            for (i in 0 until nodes.length) {
                permissions.put(generateXmlString(nodes.item(i), "manifest"))
            }
        }
        buildInfoJsonArray.getJSONObject(0).put("permissions", permissions)

        val buildInfoJsonFile =
            Paths.get(rawBuildDir.toString(), "files", "component_build_infos.json").toFile().apply {
                this.parentFile.mkdirs()
            }
        buildInfoJsonFile.writeText(buildInfoJsonArray.toString())
    }

    /**
     * Get metadata file
     *
     * @return The rush.yml file's data
     * @throws IOException If the input can't be read for some reason.
     */
    private fun metadataFile(): RushYaml {
        val rushYml = if (Paths.get(projectRoot, "rush.yml").exists()) {
            Paths.get(projectRoot, "rush.yml").toFile()
        } else {
            Paths.get(projectRoot, "rush.yaml").toFile()
        }

        return Yaml.default.decodeFromStream(RushYaml.serializer(), FileInputStream(rushYml))
    }

    /** Parses [markdown] and returns it. */
    private fun parseMdString(markdown: String): String {
        val extensionList = listOf(
            // Adds ability to convert URLs to clickable links
            AutolinkExtension.create(),
            // Adds ability to create task lists.
            TaskListItemsExtension.create()
        )

        val parser = Parser.Builder().extensions(extensionList).build()
        val renderer = HtmlRenderer.builder()
            .extensions(extensionList)
            .softbreak("<br>")
            .build()

        return renderer.render(parser.parse(markdown))
    }

    /**
     * Returns a JSON array of specific XML elements from the given list of nodes.
     *
     * @param node   A XML node, for eg., <service>
     * @param parent Name of the node whose child nodes we want to generate. This is required because
     *               getElementsByTag() method returns all the elements that satisfy the name.
     * @return A JSON array containing XML elements
     */
    private fun generateXmlString(node: Node, parent: String): String {
        // Unlike other elements, permissions aren't stored as XML strings in the build info JSON
        // file. Only the name of the permission (android:name) is stored.
        if (node.nodeName == "uses-permission") {
            val permission = node.attributes.getNamedItem("android:name")
            return if (permission != null) {
                permission.nodeValue
            } else {
                throw DOMException(
                    1.toShort(),
                    "ERR No android:name attribute found in <uses-permission>"
                )
            }
        }

        val sb = StringBuilder()
        if (node.nodeType == Node.ELEMENT_NODE && node.parentNode.nodeName == parent) {
            val element = node as Element
            val tagName = element.tagName
            sb.append("<$tagName ")

            if (element.hasAttributes()) {
                val attributes = element.attributes
                for (i in 0 until attributes.length) {
                    if (attributes.item(i).nodeType == Node.ATTRIBUTE_NODE) {
                        val attribute = attributes.item(i) as Attr
                        // Drop the "tools:sth" attributes.
                        if (!attribute.nodeName.contains("tools:")) {
                            sb.append("${attribute.nodeName} = \"${attribute.nodeValue}\" ")
                        }
                    }
                }
            }

            if (element.hasChildNodes()) {
                sb.append(" >\n")
                val children = element.childNodes
                for (j in 0 until children.length) {
                    sb.append(generateXmlString(children.item(j), element.nodeName))
                }
                sb.append("</$tagName>\n")
            } else {
                sb.append("/>\n")
            }
        }

        return sb.toString()
    }

    /**
     * Stringifies all the XML elements under <application> and returns them as a list.
     *
     * @param doc   The AndroidManifest.xml document
     */
    private fun applicationElementsXmlString(doc: Document): List<String> {
        val validTags = listOf(
            "activity",
            "activity-alias",
            "meta-data",
            "provider",
            "service",
            "receiver",
            "uses-library"
        )

        val xmlStrings = validTags.map {
            val res = mutableListOf<String>()
            val elements = doc.getElementsByTagName(it)
            for (i in 0 until elements.length) {
                res.add(generateXmlString(elements.item(i), "application"))
            }
            res
        }.flatten()

        return xmlStrings.toList()
    }
}
