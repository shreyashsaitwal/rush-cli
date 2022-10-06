package io.github.shreyashsaitwal.rush.block

import com.google.appinventor.components.annotations.SimpleProperty
import io.github.shreyashsaitwal.rush.util.Util
import io.github.shreyashsaitwal.rush.util.yailTypeOf
import shaded.org.json.JSONObject
import javax.annotation.processing.Messager
import javax.lang.model.element.ExecutableElement
import javax.lang.model.type.DeclaredType
import javax.lang.model.type.TypeKind
import javax.lang.model.util.Elements
import javax.tools.Diagnostic

enum class PropertyAccessType(val value: String) {
    READ("read-only"),
    WRITE("write-only"),
    READ_WRITE("read-write"),
    INVISIBLE("invisible");
}

class Property(
    element: ExecutableElement,
    private val messager: Messager,
    private val priorProperties: MutableList<Property>,
    private val elementUtils: Elements,
) : Block(element) {

    init { runChecks() }

    override fun runChecks() {
        if (!Util.isPascalCase(name)) {
            messager.printMessage(
                Diagnostic.Kind.WARNING,
                "Simple property \"$name\" should follow 'PascalCase' naming convention."
            )
        }

        if (description.isBlank()) {
            messager.printMessage(
                Diagnostic.Kind.WARNING,
                "Simple property \"$name\" is missing a description."
            )
        }

        val isSetter = element.returnType.kind == TypeKind.VOID
        val noOfParams = element.parameters.size

        // Total numbers of parameters for setters must be 1 and for getter must be 0.
        if (isSetter && noOfParams != 1) {
            messager.printMessage(
                Diagnostic.Kind.ERROR,
                "The total number of parameters allowed on the setter type simple property \"$name\" is: 1"
            )
        } else if (!isSetter && noOfParams != 0) {
            messager.printMessage(
                Diagnostic.Kind.ERROR,
                "The total number of parameters allowed on the getter type simple property \"$name\" is: 0"
            )
        }

        val partnerProp = priorProperties.firstOrNull {
            it.name == name && it !== this
        }

        // Return types of getters and setters must match
        if (partnerProp != null && partnerProp.returnType != returnType) {
            messager.printMessage(
                Diagnostic.Kind.ERROR,
                "Inconsistent types across getter and setter for simple property \"$name\"."
            )
        }
    }

    override val description: String
        get() {
            val desc = this.element.getAnnotation(SimpleProperty::class.java).description.let {
                it.ifBlank {
                    elementUtils.getDocComment(element) ?: ""
                }
            }
            return desc
        }

    private val returnTypeElement = when (element.returnType.kind) {
        // Setter
        TypeKind.VOID -> element.parameters[0]
        // Getter
        TypeKind.DECLARED -> (element.returnType as DeclaredType).asElement()
        else -> TODO("Unreachable")
    }

    override val helper = Helper.tryFrom(returnTypeElement)

    /**
     * The return type of property type block, defined as "type" in components.json, depends on whether it's a setter or
     * a getter. For getters, the "type" is the same as the actual return type, but for setters, it is equal to the type
     * this setter sets, i.e., it is equal to the type of its argument.
     */
    override val returnType = Util.yailTypeOf(
        // Primitive types when
        returnTypeElement.asType().toString().replace("()", ""),
        helper != null
    )

    /**
     * The access type of the current property.
     */
    private val accessType: PropertyAccessType
        get() {
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
            val partnerProp = priorProperties.firstOrNull {
                it.name == name && it !== this
            }

            // If the partner prop exists and is not invisible, then it means that both getter and setter
            // exists for this prop. In that case, we set the access type to read-write which tells AI2
            // to render two blocks -- one getter and one setter.
            if (partnerProp != null && partnerProp.accessType != PropertyAccessType.INVISIBLE) {
                accessType = PropertyAccessType.READ_WRITE
            }

            // Remove the partner prop from the prior props lst. This is necessary because AI2 doesn't
            // expect getter and setter to be defined separately. It checks the access type to decide
            // whether to generate getter (read-only), setter (write-only), both (read-write) or none
            // (invisible).
            priorProperties.remove(partnerProp)
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
    override fun asJsonObject() = JSONObject()
        .put("deprecated", deprecated.toString())
        .put("name", name)
        .put("description", description)
        .put("type", returnType)
        .put("rw", accessType.value)
        .put("helper", helper?.asJsonObject())
}
