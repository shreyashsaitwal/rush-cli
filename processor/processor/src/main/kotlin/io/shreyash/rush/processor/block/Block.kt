package io.shreyash.rush.processor.block

import io.shreyash.rush.processor.util.yailTypeOf
import shaded.org.json.JSONObject
import java.lang.Deprecated
import javax.lang.model.element.ExecutableElement
import kotlin.String

abstract class Block(val element: ExecutableElement) {

    /** Name of this block. */
    val name: String
        get() = element.simpleName.toString()

    /** The description of this block */
    abstract val description: String?

    /**
     * @return YAIL equivalent of the return type of this block.
     */
    open val returnType = if (element.returnType.toString() != "void") {
        yailTypeOf(element.returnType.toString(), HelperType.tryFrom(element) != null)
    } else {
        null
    }

    val helper = Helper.tryFrom(element)

    /** Whether this block is deprecated */
    val deprecated = element.getAnnotation(Deprecated::class.java) != null

    /** Checks that are supposed to be performed on this block */
    abstract fun runChecks()

    /**
     * @return JSON representation of this block that is later used to construct the `components.json`
     * descriptor file.
     */
    abstract fun asJsonObject(): JSONObject
}

abstract class ParameterizedBlock(element: ExecutableElement) : Block(element) {
    /**
     * @return The parameters (or arguments) of this block.
     */
    val params = this.element.parameters.map {
        val helper = Helper.tryFrom(it)
        BlockParam(
            it.simpleName.toString(),
            yailTypeOf(it.asType().toString(), helper != null),
            helper
        )
    }
}

data class BlockParam(
    val name: String,
    val type: String,
    val helper: Helper?,
) {
    fun asJsonObject(): JSONObject = JSONObject()
        .put("name", name)
        .put("type", type)
        .put("helper", helper?.data?.asJsonObject())
}
