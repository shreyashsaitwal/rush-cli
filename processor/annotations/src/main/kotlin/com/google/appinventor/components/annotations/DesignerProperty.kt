package com.google.appinventor.components.annotations

import com.google.appinventor.components.common.PropertyTypeConstants

/**
 * Annotation to mark properties to be visible in the ODE visual designer.
 *
 *
 * Only the setter method of the property must be marked with this
 * annotation.
 *
 */
@Retention(AnnotationRetention.RUNTIME)
@Target(AnnotationTarget.FUNCTION)
annotation class DesignerProperty(
    /**
     * Determines the property editor used in the designer.
     *
     * @return  property type
     */
    val editorType: String = PropertyTypeConstants.PROPERTY_TYPE_TEXT,
    /**
     * Default value of property.
     *
     * @return  default property value
     */
    val defaultValue: String = "",
    /**
     * If true, always send the property even if it is the default value. This
     * can be used for backward compatibility with older companions when the
     * default changes from one value to another.
     *
     * @return  true if the property should always been sent in code generation,
     * false if the default value needn't be sent.
     */
    val alwaysSend: Boolean = false,
    /**
     * Arguments passed to editor class.
     *
     * @return  editor arguments
     */
    val editorArgs: Array<String> = []
)
