package io.shreyash.rush.processor.block

import com.google.appinventor.components.annotations.DesignerProperty
import shaded.org.json.JSONObject
import javax.annotation.processing.Messager
import javax.lang.model.element.Element
import javax.lang.model.element.ExecutableElement
import javax.tools.Diagnostic

class DesignerProperty(
    element: ExecutableElement,
    private val messager: Messager,
    private val properties: List<Property>,
) : Block(element) {
    init {
        runChecks()
    }

    override val description: Nothing? = null

    override fun runChecks() {
        // Check if the corresponding setter simple property exists.
        val setterExist = properties.any { it.name == name }
        if (!setterExist) {
            messager.printMessage(
                Diagnostic.Kind.ERROR,
                "Unable to find corresponding @SimpleProperty annotation for designer property '$name'."
            )
        }
    }

    /**
     * @return JSON representation of this designer property.
     * {
     *  "alwaysSend": "false",
     *  "defaultValue": "Bar",
     *  "name": "Foo",
     *  "editorArgs": ["Bar", "Baz"],
     *  "editorType": "text"
     * }
     */
    override fun asJsonObject(): JSONObject {
        val annotation = element.getAnnotation(DesignerProperty::class.java)
        return JSONObject()
            .put("name", name)
            .put("editorType", annotation.editorType)
            .put("editorArgs", annotation.editorArgs)
            .put("defaultValue", annotation.defaultValue)
            .put("alwaysSend", annotation.alwaysSend.toString())
    }
}
