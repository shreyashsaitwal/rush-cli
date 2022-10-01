package io.github.shreyashsaitwal.rush.block

import io.github.shreyashsaitwal.rush.util.yailTypeOf
import shaded.org.json.JSONObject
import java.lang.Deprecated
import javax.lang.model.element.ExecutableElement
import kotlin.String

/**
 * Represents AI2 block types:
 *  - `SimpleFunction`
 *  - `SimpleEvent`
 *  - `SimpleProperty`
 *  - `DesignerProperty`
 */
abstract class Block(val element: ExecutableElement) {

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
    open val returnType = if (element.returnType.toString() != "void") {
        yailTypeOf(element.returnType.toString(), HelperType.tryFrom(element) != null)
    } else {
        null
    }

    /**
     * Helper (dropdown blocks) definition of this block.
     */
    open val helper = Helper.tryFrom(element)

    /**
     * Whether this block is deprecated.
     */
    val deprecated = element.getAnnotation(Deprecated::class.java) != null

    /**
     * Checks that are supposed to be performed on this block.
     */
    abstract fun runChecks()

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
abstract class ParameterizedBlock(element: ExecutableElement) : Block(element) {

    data class Parameter(
        val name: String,
        val type: String,
        val helper: Helper?,
    ) {
        fun asJsonObject(): JSONObject = JSONObject()
            .put("name", name)
            .put("type", type)
            .put("helper", helper?.data?.asJsonObject())
    }

    /**
     * @return The parameters of this parameterized block.
     */
    val params: List<Parameter> = this.element.parameters.map {
        val helper = Helper.tryFrom(it)
        Parameter(
            it.simpleName.toString(),
            yailTypeOf(it.asType().toString(), helper != null),
            helper
        )
    }
}
