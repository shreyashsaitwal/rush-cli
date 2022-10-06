package io.github.shreyashsaitwal.rush.block

import com.google.appinventor.components.annotations.SimpleFunction
import io.github.shreyashsaitwal.rush.util.Util
import io.github.shreyashsaitwal.rush.util.yailTypeOf
import shaded.org.json.JSONObject
import javax.annotation.processing.Messager
import javax.lang.model.element.ExecutableElement
import javax.lang.model.type.TypeKind
import javax.lang.model.util.Elements
import javax.tools.Diagnostic

class Function(
    element: ExecutableElement,
    private val messager: Messager,
    private val elementUtils: Elements,
) : ParameterizedBlock(element) {
    init {
        runChecks()
    }

    override val description: String
        get() {
            val desc = this.element.getAnnotation(SimpleFunction::class.java).description.let {
                it.ifBlank {
                    elementUtils.getDocComment(element) ?: ""
                }
            }
            return desc
        }

    override val returnType = if (element.returnType.kind == TypeKind.VOID) {
        Util.yailTypeOf(
            element.returnType.toString(),
            HelperType.tryFrom(element) != null
        )
    } else {
        null
    }

    override fun runChecks() {
        // Check method name
        if (!Util.isPascalCase(name)) {
            messager.printMessage(
                Diagnostic.Kind.WARNING,
                "Simple function \"$name\" should follow 'PascalCase' naming convention."
            )
        }

        // Check param names
        params.forEach {
            if (!Util.isCamelCase(it.name)) {
                messager.printMessage(
                    Diagnostic.Kind.WARNING,
                    "Parameter \"${it.name}\" in simple function \"$name\" should follow 'camelCase' naming convention."
                )
            }
        }

        if (description.isBlank()) {
            messager.printMessage(
                Diagnostic.Kind.WARNING,
                "Simple function \"$name\" is missing a description."
            )
        }
    }

    /**
     * @return JSON representation of this method.
     * {
     *     "deprecated": "false",
     *     "name": "Foo",
     *     "description": "This is a description",
     *     "returnType": "<any YAIL type>",
     *     "params": [
     *       { "name": "bar", "type": "number" },
     *     ],
     *     "helper": {...}
     * }
     */
    override fun asJsonObject(): JSONObject = JSONObject()
        .put("deprecated", deprecated.toString())
        .put("name", name)
        .put("description", description)
        .put("returnType", returnType)
        .put("params", this.params.map { it.asJsonObject() })
        .put("helper", helper?.asJsonObject())
}
