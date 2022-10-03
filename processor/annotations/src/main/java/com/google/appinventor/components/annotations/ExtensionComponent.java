package com.google.appinventor.components.annotations;

import java.lang.annotation.ElementType;
import java.lang.annotation.Retention;
import java.lang.annotation.RetentionPolicy;
import java.lang.annotation.Target;

/**
 * Annotation used to mark a class as an App Inventor extension.
 */
@Retention(RetentionPolicy.RUNTIME)
@Target(ElementType.TYPE)
public @interface ExtensionComponent {
    /**
     * The name of the extension. This is the name that will be displayed in the designer and blocks editor.
     *
     * @return the name of the extension
     */
    String name();

    /**
     * The description of the extension. This is the description that will be displayed in the designer.
     *
     * @return the description of the extension
     */
    String description() default "";

    /**
     * Path to the icon for the extension. The icon must be stored in the `assets` directory.
     *
     * @return the path to the icon for the extension
     */
    String icon() default "";
}
