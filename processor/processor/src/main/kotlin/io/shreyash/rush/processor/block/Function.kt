package io.shreyash.rush.processor.block

import com.google.appinventor.components.annotations.SimpleFunction
import io.shreyash.rush.processor.util.isCamelCase
import io.shreyash.rush.processor.util.isPascalCase
import shaded.org.json.JSONObject
import javax.annotation.processing.Messager
import javax.lang.model.element.ExecutableElement
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

    override fun runChecks() {
        // Check method name
        if (!isPascalCase(name)) {
            messager.printMessage(
                Diagnostic.Kind.WARNING,
                "Simple function \"$name\" should follow 'PascalCase' naming convention."
            )
        }

        // Check param names
        params.forEach {
            if (!isCamelCase(it.name)) {
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
     *  "name": "Foo",
     *  "description": "This is a description",
     *  "deprecated": "false",
     *  "returnType": "any",
     *  "params": [
     *    { "name": "bar", "type": "number" },
     *  ]
     * }
     */
    override fun asJsonObject(): JSONObject = JSONObject()
        .put("name", name)
        .put("description", description)
        .put("deprecated", deprecated.toString())
        .put("params", this.params.map { it.asJsonObject() })
        .put("returnType", returnType)
        .put("helper", helper)
}
