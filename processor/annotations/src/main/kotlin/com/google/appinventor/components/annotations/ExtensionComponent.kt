package com.google.appinventor.components.annotations

/**
 * Annotation used to mark a class as an App Inventor extension.
 */
@Retention(AnnotationRetention.RUNTIME)
@Target(AnnotationTarget.CLASS)
annotation class ExtensionComponent(
    val name: String,
    val description: String = "",
    val icon: String = "",
)
