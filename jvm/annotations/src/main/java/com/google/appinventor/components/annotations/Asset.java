package com.google.appinventor.components.annotations;

import java.lang.annotation.ElementType;
import java.lang.annotation.Retention;
import java.lang.annotation.RetentionPolicy;
import java.lang.annotation.Target;

/**
 * Annotation used to mark a parameter as accepting an asset string. This can be used to upgrade old
 * components (i.e. components that were released before this was released). It can also be included
 * in new components.
 */
@Retention(RetentionPolicy.RUNTIME)
@Target({ElementType.PARAMETER})
public @interface Asset {
    /**
     * If specified, a list of extensions used to filter the asset list by.
     *
     * @return an empty array (the default) or an array of file extensions used to filter the assets
     */
    String[] value() default {};
}