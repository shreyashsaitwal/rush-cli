package io.shreyash.rush.processor.block

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
import javax.lang.model.type.TypeKind
import javax.lang.model.type.TypeMirror

enum class HelperType {
    OPTION_LIST, ASSET;

    companion object {
        fun tryFrom(element: Element): HelperType? {
            val type = if (element is ExecutableElement) element.returnType else element.asType()
            return if (element.getAnnotation(Asset::class.java) != null) {
                ASSET
            } else if (element.getAnnotation(Options::class.java) != null) {
                OPTION_LIST
            } else if (type.kind == TypeKind.DECLARED) {
                val el = (type as DeclaredType).asElement() as TypeElement
                val isOptionList = el.interfaces.any {
                    val ty = (it as DeclaredType).asElement() as TypeElement
                    ty.simpleName.toString() == "OptionList"
                }
                if (isOptionList) OPTION_LIST else null
            } else {
                return null
            }
        }
    }
}

data class Helper(
    val type: HelperType,
    val data: HelperData,
) {
    fun asJsonObject(): JSONObject {
        return JSONObject()
            .put("type", type.toString())
            .put("data", data.asJsonObject())
    }

    companion object {
        fun tryFrom(element: Element): Helper? {
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

                    val optionListEnumName = if (optionsAnnotation != null) {
                        var elem: Element? = null
                        try {
                            // This will always throw. For more info: https://stackoverflow.com/a/10167558/12401482
                            optionsAnnotation.value
                        } catch (e: MirroredTypeException) {
                            elem = (e.typeMirror as DeclaredType).asElement()
                        }

                        // This will never be null, don't listen to IntelliJ
                        elem!!.asType().toString()
                    } else if (element is ExecutableElement) {
                        element.returnType.toString()
                    } else {
                        element.asType().toString()
                    }

                    val data = if (HelperSingleton.optionListCache.containsKey(optionListEnumName)) {
                        HelperSingleton.optionListCache[optionListEnumName]!!
                    } else {
                        OptionListData(element).apply {
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

class AssetData(private val fileExtensions: Array<String> = arrayOf()) : HelperData() {
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
     * This stores [OptionListData]s of enums that have already been processed.
     */
    val optionListCache = mutableMapOf<String, OptionListData>()

    val loader: ClassLoader

    init {
        val classesDir = Paths.get(System.getenv("RUSH_PROJECT_ROOT"), ".rush", "build", "classes")
        val libDir = Paths.get(System.getenv("RUSH_HOME"), "libs")

        val annotationsJar = Paths.get(libDir.toString(), "annotations.jar")
        val runtimeJar = Paths.get(libDir.toString(), "runtime.jar")

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

class OptionListData(private val element: Element) : HelperData() {

    data class Option(
        val deprecated: Boolean,
        val name: String,
        val value: String,
    ) {
        fun asJsonObject(): JSONObject {
            return JSONObject()
                .put("name", name)
                .put("deprecated", deprecated)
                .put("value", value)
                .put("description", "") // Getting enum consts' description doesn't work (also not in AI2's ap)
        }
    }

    private lateinit var defaultOption: String

    private lateinit var underlyingType: String

    private val elementType: TypeMirror = if (element is ExecutableElement) {
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

        val enumConsts =
            optionListEnum.enumConstants.associate { Pair(it.toString(), toValueMethod.invoke(it).toString()) }

        // We need the enum elements only for finding which enum const has the Default annotation.
        val enclosedElements = (elementType as DeclaredType).asElement().enclosedElements
        val enumElements = enclosedElements.filter { enumConsts.containsKey(it.simpleName.toString()) }

        defaultOption = enumElements.singleOrNull { it.getAnnotation(Default::class.java) != null }
            ?.simpleName?.toString() ?: enumConsts.keys.first()

        // The typeName property returns name like this: com.google.appinventor.components.common.OptionList<java.lang.String>
        // We only need the generic type's name, ie, the part inside <>.
        underlyingType = optionListEnum.genericInterfaces.first().typeName.split("[<>]".toPattern())[1]

        return enumConsts.map {
            Option(
                deprecated = element.getAnnotation(Deprecated::class.java) != null,
                name = it.key,
                value = it.value,
            ).asJsonObject()
        }
    }

    override fun asJsonObject(): JSONObject {
        val enumName = elementType.toString().split(".").last()
        return JSONObject()
            .put("className", elementType.toString())
            .put("key", enumName)
            .put("tag", enumName)
            .put("options", options())
            .put("underlyingType", underlyingType)
            .put("defaultOpt", defaultOption)
    }
}
