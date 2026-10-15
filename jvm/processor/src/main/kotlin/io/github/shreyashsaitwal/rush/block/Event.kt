package io.github.shreyashsaitwal.rush.block

import com.google.appinventor.components.annotations.SimpleEvent
import io.github.shreyashsaitwal.rush.Utils
import org.json.JSONObject
import javax.annotation.processing.Messager
import javax.lang.model.element.ExecutableElement
import javax.lang.model.type.TypeKind
import javax.lang.model.util.Elements
import javax.tools.Diagnostic.Kind

class Event(
    element: ExecutableElement,
    messager: Messager,
    elementUtils: Elements,
) : ParameterizedBlock(element, messager, elementUtils) {

    init {
        runChecks()
    }

    override val description: String
        get() {
            val desc = element.getAnnotation(SimpleEvent::class.java).description.let {
                it.ifBlank {
                    elementUtils.getDocComment(element) ?: ""
                }
            }
            return desc
        }

    override val returnType = if (element.returnType.kind != TypeKind.VOID) {
        Utils.yailTypeOf(
            element,
            element.returnType,
            HelperType.tryFrom(element) != null,
            messager
        )
    } else {
        null
    }

    override fun runChecks() {
        super.runChecks()

        if (description.isBlank() && !deprecated) {
            messager.printMessage(Kind.WARNING, "Event has no description.", element)
        }
    }

    /**
     * @return JSON representation of this event.
     *
     * JSON:
     * {
     *     "deprecated": "false",
     *     "name": "Foo",
     *     "description": "This is a description",
     *     "params": [
     *       { "name": "bar", "type": "number" },
     *     ]
     * }
     */
    override fun asJsonObject(): JSONObject = JSONObject()
        .put("deprecated", deprecated.toString())
        .put("name", name)
        .put("description", description)
        .put("params", params.map { it.asJsonObject() })
}
