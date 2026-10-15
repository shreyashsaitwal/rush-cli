package com.google.appinventor.components.annotations;

import java.lang.annotation.ElementType;
import java.lang.annotation.Retention;
import java.lang.annotation.RetentionPolicy;
import java.lang.annotation.Target;

/**
 * Annotation to mark properties to be visible in the ODE visual designer. Only the setter method of the property must
 * be marked with this annotation.
 */
@Retention(RetentionPolicy.RUNTIME)
@Target(ElementType.METHOD)
public @interface DesignerProperty {
    /**
     * Determines the property editor used in the designer.
     *
     * @return property type
     */
    String editorType() default "text";

    /**
     * Default value of property.
     *
     * @return default property value
     */
    String defaultValue() default "";

    /**
     * If true, always send the property even if it is the default value. This
     * can be used for backward compatibility with older companions when the
     * default changes from one value to another.
     *
     * @return true if the property should always been sent in code generation,
     * false if the default value needn't be sent.
     */
    boolean alwaysSend() default false;

    /**
     * Arguments passed to editor class.
     *
     * @return editor arguments
     */
    String[] editorArgs() default {};
}
