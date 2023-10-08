package io.github.shreyashsaitwal.rush.block

import com.google.appinventor.components.annotations.SimpleProperty
import io.github.shreyashsaitwal.rush.Utils
import org.json.JSONObject
import javax.annotation.processing.Messager
import javax.lang.model.element.ExecutableElement
import javax.lang.model.element.TypeElement
import javax.lang.model.type.DeclaredType
import javax.lang.model.type.TypeKind
import javax.lang.model.util.Elements
import javax.tools.Diagnostic.Kind

private enum class PropertyAccessType(val value: String) {
    READ("read-only"),
    WRITE("write-only"),
    READ_WRITE("read-write"),
    INVISIBLE("invisible");
}

private val processedProperties = mutableListOf<Property>()

class Property(
    element: ExecutableElement,
    messager: Messager,
    elementUtils: Elements,
) : Block(element, messager, elementUtils) {

    private val accessType: PropertyAccessType

    init {
        accessType = propertyAccessType()
        runChecks()
        processedProperties.add(this)
    }

    override fun runChecks() {
        super.runChecks()

        if (description.isBlank()) {
            messager.printMessage(Kind.WARNING, "Property has no description.", element)
        }

        val isSetter = element.returnType.kind == TypeKind.VOID
        val noOfParams = element.parameters.size

        // Total numbers of parameters for setters must be 1 and for getter must be 0.
        if (isSetter && noOfParams != 1) {
            messager.printMessage(Kind.ERROR, "Setter type properties should have exactly 1 parameter.", element)
        } else if (!isSetter && noOfParams != 0) {
            messager.printMessage(Kind.ERROR, "Getter type properties should have no parameters.", element)
        }

        val partnerProp = processedProperties.firstOrNull {
            it.name == name && it !== this
        }

        // Return types of getters and setters must match
        if (partnerProp != null && partnerProp.returnType != returnType) {
            messager.printMessage(Kind.ERROR, "Inconsistent types across getter and setter for property.", element)
        }
    }

    override val description: String
        get() {
            val desc = element.getAnnotation(SimpleProperty::class.java).description.let {
                it.ifBlank {
                    elementUtils.getDocComment(element) ?: ""
                }
            }
            return desc
        }

    override val helper = when (element.returnType.kind) {
        // Setters
        TypeKind.VOID -> Helper.tryFrom(element.parameters[0], elementUtils)
        // Getters with [DeclaredType] return type
        TypeKind.DECLARED -> Helper.tryFrom((element.returnType as DeclaredType).asElement() as TypeElement, elementUtils)
        // Getters with primitive return type
        else -> Helper.tryFrom(element, elementUtils)
    }

    /**
     * The return type of property type block, defined as "type" in components.json, depends on whether it's a setter or
     * a getter. For getters, the "type" is the same as the actual return type, but for setters, it is equal to the type
     * this setter sets, i.e., it is equal to the type of its argument.
     */
    override val returnType = when (element.returnType.kind) {
        TypeKind.VOID -> Utils.yailTypeOf(
            element.parameters[0],
            element.parameters[0].asType(),
            helper != null,
            messager,
        )

        else -> Utils.yailTypeOf(element, element.returnType, helper != null, messager)
    }

    /**
     * The access type of the current property.
     */
    private fun propertyAccessType(): PropertyAccessType {
        val invisible = !element.getAnnotation(SimpleProperty::class.java).userVisible
        if (invisible) {
            return PropertyAccessType.INVISIBLE
        }

        var accessType = if (element.returnType.kind == TypeKind.VOID) {
            PropertyAccessType.WRITE
        } else {
            PropertyAccessType.READ
        }

        // If the current property is a setter, this could be a getter and vice versa.
        val partnerProp = processedProperties.firstOrNull {
            it.name == name && it !== this
        }

        // If the partner prop exists and is not invisible, then it means that both getter and setter
        // exists for this prop. In that case, we set the access type to read-write which tells AI2
        // to render two blocks -- one getter and one setter.
        if (partnerProp != null && partnerProp.accessType != PropertyAccessType.INVISIBLE) {
            accessType = PropertyAccessType.READ_WRITE
        }

        // Remove the partner prop from the prior props list. This is necessary because AI2 doesn't
        // expect getter and setter to be defined separately. It checks the access type to decide
        // whether to generate getter (read-only), setter (write-only), both (read-write) or none
        // (invisible).
        processedProperties.remove(partnerProp)
        return accessType
    }

    /**
     * @return JSON representation of this property.
     * {
     *     "rw": "read-only",
     *     "deprecated": "false",
     *     "name": "Foo",
     *     "description": "",
     *     "type": "<some YAIL type>",
     *     "helper": {...}
     * }
     */
    override fun asJsonObject(): JSONObject = JSONObject()
        .put("deprecated", deprecated.toString())
        .put("name", name)
        .put("description", description)
        .put("type", returnType)
        .put("rw", accessType.value)
        .put("helper", helper?.asJsonObject())
}
