package io.github.shreyashsaitwal.rush.block

import com.google.appinventor.components.annotations.SimpleFunction
import io.github.shreyashsaitwal.rush.Utils
import org.json.JSONObject
import javax.annotation.processing.Messager
import javax.lang.model.element.ExecutableElement
import javax.lang.model.type.DeclaredType
import javax.lang.model.type.TypeKind
import javax.lang.model.type.TypeMirror
import javax.lang.model.util.Elements
import javax.tools.Diagnostic.Kind

class Function(
    element: ExecutableElement,
    messager: Messager,
    elementUtils: Elements,
) : ParameterizedBlock(element, messager, elementUtils) {

    init {
        runChecks()
    }

    override val description: String
        get() {
            val desc = element.getAnnotation(SimpleFunction::class.java).description.let {
                it.ifBlank {
                    elementUtils.getDocComment(element) ?: ""
                }
            }
            return desc
        }

    override val returnType: String?
        get() {
            val helper = Helper.tryFrom(element, elementUtils)

            return if (continuation != null) {
                if (element.returnType.kind != TypeKind.VOID) {
                    messager.printMessage(Kind.ERROR, "Functions with continuation must be void.", element)
                }
                continuationResultType()?.let {
                    Utils.yailTypeOf(element, it, helper != null, messager, true)
                }
            } else if (element.returnType.kind != TypeKind.VOID) {
                Utils.yailTypeOf(element, element.returnType, helper != null, messager)
            } else {
                null
            }
        }

    override fun runChecks() {
        super.runChecks()

        if (description.isBlank() && !deprecated) {
            messager.printMessage(Kind.WARNING, "Function has no description.", element)
        }

        val continuations = params.filter { it.type == "continuation" }
        if (continuations.size > 1 && !deprecated) {
            messager.printMessage(
                Kind.WARNING, "Function should not have more than one continuation parameter.", element
            )
        }
        continuations.firstOrNull()?.apply {
            val typeArgs = (element.asType() as DeclaredType).typeArguments
            if (typeArgs.isEmpty()) {
                messager.printMessage(
                    Kind.ERROR,
                    "Continuation parameter must be specialized with a type, for e.g. `Continuation<Boolean>`.",
                    element
                )
            }
        }
    }

    private val continuation
        get() = params.firstOrNull { it.type == "continuation" }

    private fun continuationResultType(): TypeMirror? =
        (continuation?.element?.asType() as DeclaredType?)?.typeArguments?.firstOrNull()
            ?.takeUnless { it.toString() == "java.lang.Void" }

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
        .put("params", params.filter { it.type != "continuation" }.map { it.asJsonObject() })
        .put("continuation", if (continuation != null) true else null)
        .put("helper", helper?.asJsonObject())
}
