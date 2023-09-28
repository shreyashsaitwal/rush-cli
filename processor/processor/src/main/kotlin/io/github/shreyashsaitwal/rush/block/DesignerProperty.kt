package io.github.shreyashsaitwal.rush.block

import com.google.appinventor.components.annotations.DesignerProperty
import shaded.org.json.JSONObject
import javax.annotation.processing.Messager
import javax.lang.model.element.ExecutableElement
import javax.lang.model.util.Elements
import javax.tools.Diagnostic.Kind

class DesignerProperty(
    element: ExecutableElement,
    messager: Messager,
    elementUtils: Elements,
    private val properties: List<Property>,
) : Block(element, messager, elementUtils) {

    init {
        runChecks()
    }

    override val description: Nothing? = null

    override val returnType: Nothing? = null

    override fun runChecks() {
        // No need to invoke super.runChecks() as other checks will be done by the corresponding SimpleProperty.

        // Check if the corresponding setter simple property exists.
        val setterExist = properties.any { it.name == name }
        if (!setterExist) {
            messager.printMessage(
                Kind.ERROR,
                "Unable to find corresponding `@SimpleProperty` annotation for designer property.",
                element
            )
        }
    }

    /**
     * @return JSON representation of this designer property.
     * {
     *     "name": "Foo",
     *     "defaultValue": "Bar",
     *     "editorType": "text"
     *     "editorArgs": ["Bar", "Baz"],
     *     "alwaysSend": "false",
     * }
     */
    override fun asJsonObject(): JSONObject {
        val annotation = element.getAnnotation(DesignerProperty::class.java)
        return JSONObject()
            .put("name", name)
            .put("defaultValue", annotation.defaultValue)
            .put("editorType", annotation.editorType)
            .put("editorArgs", annotation.editorArgs)
            .put("alwaysSend", annotation.alwaysSend.toString())
    }
}
