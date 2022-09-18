package com.google.appinventor.components.annotations

/**
 * Annotation to mark Simple properties.
 *
 * Both the getter and the setter method of the property need to be marked
 * with this annotation.
 */
@Retention(AnnotationRetention.RUNTIME)
@Target(AnnotationTarget.FUNCTION)
annotation class SimpleProperty(
    /**
     * If non-empty, description to use in user-level documentation.
     */
    val description: String = "",
    /**
     * If false, this property should not be accessible through Codeblocks.
     * This was added to support the Row and Column properties, so they could
     * be indirectly set in the Designer but not accessed in Codeblocks.
     */
    val userVisible: Boolean = true
)
