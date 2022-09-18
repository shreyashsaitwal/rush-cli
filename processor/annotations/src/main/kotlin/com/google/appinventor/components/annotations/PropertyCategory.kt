package com.google.appinventor.components.annotations

/**
 * Categories for Simple properties. This is used only for documentation.
 */
enum class PropertyCategory(val value: String) {
    BEHAVIOR("Behavior"),
    APPEARANCE("Appearance"),
    DEPRECATED("Deprecated"),
    UNSET("Unspecified");

    fun getName() = value
}
