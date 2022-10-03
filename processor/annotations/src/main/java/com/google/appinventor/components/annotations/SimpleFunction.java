package com.google.appinventor.components.annotations;

import java.lang.annotation.ElementType;
import java.lang.annotation.Retention;
import java.lang.annotation.RetentionPolicy;
import java.lang.annotation.Target;

/**
 * Annotation to mark Simple functions.
 */
@Retention(RetentionPolicy.RUNTIME)
@Target(ElementType.METHOD)
public @interface SimpleFunction {
    /**
     * If non-empty, description to use in user-level documentation in place of Javadoc, which is meant for developers.
     *
     * @return the description of the function
     */
    String description() default "";
}