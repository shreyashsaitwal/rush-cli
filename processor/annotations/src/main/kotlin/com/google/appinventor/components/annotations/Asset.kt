package com.google.appinventor.components.annotations

/**
 * Annotation used to mark a parameter as accepting an asset string. This can be used to upgrade old
 * components (i.e. components that were released before this was released). It can also be included
 * in new components.
 */
@Retention(AnnotationRetention.RUNTIME)
@Target(AnnotationTarget.TYPE, AnnotationTarget.VALUE_PARAMETER)
annotation class Asset(
    val value: Array<String> = []
)
