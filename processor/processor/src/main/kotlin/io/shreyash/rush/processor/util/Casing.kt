package io.shreyash.rush.processor.util

import java.util.regex.Pattern

/**
 * Returns true if the [text] follows camel case naming convention. For e.g., fooBar.
 */
fun isCamelCase(text: String): Boolean {
    val pattern = Pattern.compile(
        """^[a-z]([A-Z0-9]*[a-z][a-z0-9]*[A-Z]|[a-z0-9]*[A-Z][A-Z0-9]*[a-z])?[A-Za-z0-9]*$"""
    )
    return pattern.matcher(text).find()
}

/**
 * Returns true if the [text] follows pascal case naming convention. For e.g., FooBar.
 */
fun isPascalCase(text: String): Boolean {
    val pattern = Pattern.compile(
        """^[A-Z]([A-Z0-9]*[a-z][a-z0-9]*[A-Z]|[a-z0-9]*[A-Z][A-Z0-9]*[a-z])?[A-Za-z0-9]*$"""
    )
    return pattern.matcher(text).find()
}
