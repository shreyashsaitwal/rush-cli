package io.github.shreyashsaitwal.rush.block

import com.google.appinventor.components.annotations.Asset
import com.google.appinventor.components.annotations.Options
import com.google.appinventor.components.common.Default
import shaded.org.json.JSONArray
import shaded.org.json.JSONObject
import java.lang.reflect.Method
import java.net.URLClassLoader
import java.nio.file.Paths
import javax.lang.model.element.Element
import javax.lang.model.element.ExecutableElement
import javax.lang.model.element.TypeElement
import javax.lang.model.type.DeclaredType
import javax.lang.model.type.MirroredTypeException
import javax.lang.model.util.Elements

/**
 * Possible types of helper blocks.
 */
enum class HelperType {
    OPTION_LIST, ASSET;

    companion object {

        /**
         * @return Appropriate [HelperType] for the [element] if it's an option list enum or if it's annotated with
         * [Options] or [Asset] annotation, otherwise, null.
         */
        fun tryFrom(element: Element): HelperType? {
            val type = if (element is ExecutableElement) {
                element.returnType
            } else {
                element.asType()
            }

            if (element.getAnnotation(Asset::class.java) != null) {
                return ASSET
            } else if (element.getAnnotation(Options::class.java) != null) {
                return OPTION_LIST
            }

            // Element doesn't have any of the above annotation, check if it's type is an option list enum.
            if (type is DeclaredType) {
                val typeElement = type.asElement() as TypeElement
                val isOptionList = typeElement.interfaces.any {
                    val interfaceTypeElement = (it as DeclaredType).asElement() as TypeElement
                    interfaceTypeElement.simpleName.toString() == "OptionList"
                }
                if (isOptionList) return OPTION_LIST
            }

            return null
        }
    }
}

/**
 * Represents the helper definition of a [Block]. For more information on what helpers are (aka dropdown blocks) check
 * out this post on AI2 community:
 * https://community.appinventor.mit.edu/t/what-is-your-opinion-about-helper-blocks-in-app-inventor-gsoc-project-user-feedback/9057
 */
data class Helper(
    private val type: HelperType,
    private val data: HelperData,
) {
    fun asJsonObject(): JSONObject {
        return JSONObject()
            .put("type", type.toString())
            .put("data", data.asJsonObject())
    }

    companion object {

        /**
         * @return Generates [Helper] from [element] if it is of valid [HelperType], otherwise null.
         */
        fun tryFrom(element: Element, elementUtils: Elements): Helper? {
            val helperType = HelperType.tryFrom(element)
            return when (helperType) {
                HelperType.ASSET -> {
                    val helper = Helper(
                        type = helperType,
                        data = AssetData(element.getAnnotation(Asset::class.java).value)
                    )
                    helper
                }

                HelperType.OPTION_LIST -> {
                    val optionsAnnotation = element.getAnnotation(Options::class.java)
                    var helperElement = element

                    val optionListEnumName = if (optionsAnnotation != null) {
                        try {
                            // This will always throw. For more info: https://stackoverflow.com/a/10167558/12401482
                            optionsAnnotation.value
                        } catch (e: MirroredTypeException) {
                            helperElement = (e.typeMirror as DeclaredType).asElement()
                        }

                        helperElement.asType().toString()
                    } else {
                        val type = if (element is ExecutableElement) {
                            element.returnType
                        } else {
                            element.asType()
                        }
                        type.toString()
                    }

                    val isCached = HelperSingleton.optionListCache.containsKey(optionListEnumName)
                    val data = if (isCached) {
                        HelperSingleton.optionListCache[optionListEnumName]!!
                    } else {
                        OptionListData(helperElement, elementUtils).apply {
                            HelperSingleton.optionListCache.putIfAbsent(optionListEnumName, this)
                        }
                    }

                    val helper = Helper(helperType, data)
                    helper
                }

                else -> null
            }
        }
    }
}

abstract class HelperData {
    abstract fun asJsonObject(): JSONObject
}

private class AssetData(private val fileExtensions: Array<String> = arrayOf()) : HelperData() {
    override fun asJsonObject(): JSONObject {
        return if (fileExtensions.isEmpty())
            JSONObject()
        else
            JSONObject().put("filter", JSONArray().apply {
                for (ext in fileExtensions) {
                    this.put(ext)
                }
            })
    }
}

private object HelperSingleton {
    /**
     * This stores [OptionListData]s of helpers that have already been processed.
     */
    val optionListCache = mutableMapOf<String, OptionListData>()

    val loader: ClassLoader

    init {
        val classesDir = Paths.get(System.getenv("RUSH_PROJECT_ROOT"), ".rush", "build", "classes")
        val annotationsJar = Paths.get(System.getenv("RUSH_ANNOTATIONS_JAR"))
        val runtimeJar = Paths.get(System.getenv("RUSH_RUNTIME_JAR"))

        // TODO: Should the external dependencies be added as well?

        loader = URLClassLoader(
            arrayOf(
                classesDir.toUri().toURL(),
                annotationsJar.toUri().toURL(),
                runtimeJar.toUri().toURL()
            )
        )
    }
}

private class OptionListData(element: Element, private val elementUtils: Elements) : HelperData() {

    data class Option(
        val deprecated: Boolean,
        val name: String,
        val value: String,
    ) {
        fun asJsonObject(): JSONObject {
            return JSONObject()
                .put("name", name)
                .put("deprecated", deprecated.toString())
                .put("value", value)
                .put("description", "Option for $name") // Getting enum consts' description doesn't work (also not in AI2)
        }
    }

    private lateinit var defaultOption: String

    private lateinit var underlyingType: String

    private val elementType = if (element is ExecutableElement) {
        element.returnType
    } else {
        element.asType()
    }

    private fun options(): List<JSONObject> {
        val optionListEnumName = elementType.toString()
        val optionListEnum: Class<*>
        val toValueMethod: Method
        try {
            optionListEnum = HelperSingleton.loader.loadClass(optionListEnumName)
            toValueMethod = optionListEnum.getDeclaredMethod("toUnderlyingValue")
        } catch (e: Exception) {
            throw e
        }

        if (!optionListEnum.isEnum) {
            throw Exception("OptionList is not an enum: $optionListEnumName")
        }

        val enumConsts = optionListEnum.enumConstants.associate {
            it.toString() to toValueMethod.invoke(it).toString()
        }

        // We need the enum elements only for finding which enum const has the Default annotation.
        val enclosedElements = (elementType as DeclaredType).asElement().enclosedElements
        val enumElements = enclosedElements.filter { enumConsts.containsKey(it.simpleName.toString()) }

        defaultOption = enumElements
            .singleOrNull { it.getAnnotation(Default::class.java) != null }
            ?.simpleName?.toString() ?: enumConsts.keys.first()

        // The typeName property returns name like this: com.google.appinventor.components.common.OptionList<java.lang.String>
        // We only need the generic type's name, ie, the part inside <>.
        underlyingType = optionListEnum.genericInterfaces.first().typeName.split("[<>]".toPattern())[1]

        return enumConsts.map {
            Option(
                deprecated = elementUtils.isDeprecated(enumElements.singleOrNull { el ->
                    el.simpleName.toString() == it.key
                }),
                name = it.key,
                value = it.value,
            ).asJsonObject()
        }
    }

    override fun asJsonObject(): JSONObject {
        val enumName = elementType.toString().split(".").last()
        val opts = options()
        return JSONObject()
            .put("className", elementType.toString())
            .put("underlyingType", underlyingType)
            .put("defaultOpt", defaultOption)
            .put("options", opts)
            .put("key", enumName)
            .put("tag", enumName)
    }
}
