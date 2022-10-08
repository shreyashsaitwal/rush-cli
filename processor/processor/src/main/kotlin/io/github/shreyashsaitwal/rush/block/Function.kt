package io.github.shreyashsaitwal.rush.block

import com.google.appinventor.components.annotations.SimpleFunction
import io.github.shreyashsaitwal.rush.Utils
import shaded.org.json.JSONObject
import javax.annotation.processing.Messager
import javax.lang.model.element.ExecutableElement
import javax.lang.model.type.DeclaredType
import javax.lang.model.type.TypeKind
import javax.lang.model.type.TypeMirror
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

    override val returnType: String?
        get() {
            val continuationType = continuationUnderlyingType()
            val helper = Helper.tryFrom(element)

            return if (continuationType != null) {
                if (element.returnType.kind != TypeKind.VOID) {
                    messager.printMessage(Diagnostic.Kind.ERROR, "Methods with continuation must be void.", element)
                }
                Utils.yailTypeOf(continuationType, helper != null, true)
            } else if (element.returnType.kind != TypeKind.VOID) {
                Utils.yailTypeOf(element.returnType, helper != null)
            } else {
                null
            }
        }

    override fun runChecks() {
        // Check method name
        if (!Utils.isPascalCase(name)) {
            messager.printMessage(
                Diagnostic.Kind.WARNING,
                "Simple function \"$name\" should follow 'PascalCase' naming convention."
            )
        }

        // Check param names
        params.forEach {
            if (!Utils.isCamelCase(it.name)) {
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

        val continuations = params.filter { it.type == "continuation" }
        if (continuations.size > 1) {
            messager.printMessage(
                Diagnostic.Kind.WARNING,
                "Method should not have more than one continuation parameter.",
                element
            )
        }
        continuations.first().apply {
            val typeArgs = (this.element.asType() as DeclaredType).typeArguments
            if (typeArgs.isEmpty()) {
                messager.printMessage(
                    Diagnostic.Kind.ERROR,
                    "Continuation parameter must be specialized with a type.",
                    element
                )
            }
        }
    }

    private fun continuationUnderlyingType(): TypeMirror? {
        return params.firstOrNull { it.type == "continuation" }?.let {
            val typeArgs = (it.element.asType() as DeclaredType).typeArguments
            if (typeArgs.first().kind != TypeKind.VOID) {
                typeArgs.first()
            } else {
                null
            }
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
        .put("params", this.params.filter { it.type != "continuation" }.map { it.asJsonObject() })
        .put("continuation", continuationUnderlyingType() != null)
        .put("helper", helper?.asJsonObject())
}
