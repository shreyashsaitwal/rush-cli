package io.github.shreyashsaitwal.rush.block

import io.github.shreyashsaitwal.rush.Utils
import org.json.JSONObject
import javax.annotation.processing.Messager
import javax.lang.model.element.ExecutableElement
import javax.lang.model.element.Modifier
import javax.lang.model.element.VariableElement
import javax.lang.model.util.Elements
import javax.tools.Diagnostic

/**
 * Represents AI2 block types:
 *  - `SimpleFunction`
 *  - `SimpleEvent`
 *  - `SimpleProperty`
 *  - `DesignerProperty`
 */
abstract class Block(val element: ExecutableElement, val messager: Messager, val elementUtils: Elements) {

    /**
     * Name of this block.
     */
    val name = element.simpleName.toString()

    /**
     * The description of this block
     */
    abstract val description: String?

    /**
     * YAIL equivalent of the return type of this block.
     */
    abstract val returnType: String?

    /**
     * Helper (dropdown blocks) definition of this block.
     */
    open val helper = Helper.tryFrom(element, elementUtils)

    /**
     * Whether this block is deprecated.
     */
    val deprecated = elementUtils.isDeprecated(element)

    /**
     * Checks that are supposed to be performed on this block.
     */
    open fun runChecks() {
        val type = this::class.java.simpleName.toString()

        if (!Utils.isPascalCase(name)) {
            messager.printMessage(
                Diagnostic.Kind.WARNING,
                "$type should follow `PascalCase` naming convention.",
                element
            )
        }

        if (!element.modifiers.contains(Modifier.PUBLIC)) {
            messager.printMessage(Diagnostic.Kind.ERROR, "$type should be public.", element)
        }
    }

    /**
     * @return JSON representation of this block that is later used to construct the `components.json` descriptor file.
     */
    abstract fun asJsonObject(): JSONObject
}

/**
 * Represents blocks that may have one or more parameters:
 *  - `SimpleFunction`
 *  - `SimpleEvent`
 */
abstract class ParameterizedBlock(element: ExecutableElement, messager: Messager, elementUtil: Elements) :
    Block(element, messager, elementUtil) {

    data class Parameter(
        val element: VariableElement,
        val name: String,
        val type: String,
        val helper: Helper?,
    ) {
        fun asJsonObject(): JSONObject = JSONObject()
            .put("name", name)
            .put("type", type)
            .put("helper", helper?.asJsonObject())
    }

    override fun runChecks() {
        super.runChecks()

        val type = this::class.java.simpleName.toString()
        params.forEach {
            if (!Utils.isCamelCase(it.name)) {
                messager.printMessage(
                    Diagnostic.Kind.WARNING,
                    "$type parameters should follow `camelCase` naming convention.",
                    it.element
                )
            }
        }
    }

    /**
     * @return The parameters of this parameterized block.
     */
    val params: List<Parameter> = element.parameters.map {
        val helper = Helper.tryFrom(it, elementUtil)
        Parameter(
            it,
            it.simpleName.toString(),
            Utils.yailTypeOf(it, it.asType(), helper != null, messager)!!,
            helper
        )
    }
}
