package com.google.appinventor.components.common

enum class ComponentCategory(val value: String) {
    USERINTERFACE("User Interface"),
    LAYOUT("Layout"),
    MEDIA("Media"),
    ANIMATION("Drawing and Animation"),
    MAPS("Maps"),
    SENSORS("Sensors"),
    SOCIAL("Social"),
    STORAGE("Storage"),
    CONNECTIVITY("Connectivity"),
    LEGOMINDSTORMS("LEGO\u00AE MINDSTORMS\u00AE"),
    EXPERIMENTAL("Experimental"),
    EXTENSION("Extension"),
    INTERNAL("For internal use only"),
    UNINITIALIZED("Uninitialized");

    companion object {
        // Mapping of component categories to names consisting only of lower-case letters,
        // suitable for appearing in URLs.
        private val DOC_MAP: MutableMap<String, String> = HashMap()

        init {
            DOC_MAP["User Interface"] = "userinterface"
            DOC_MAP["Layout"] = "layout"
            DOC_MAP["Media"] = "media"
            DOC_MAP["Drawing and Animation"] = "animation"
            DOC_MAP["Maps"] = "maps"
            DOC_MAP["Sensors"] = "sensors"
            DOC_MAP["Social"] = "social"
            DOC_MAP["Storage"] = "storage"
            DOC_MAP["Connectivity"] = "connectivity"
            DOC_MAP["LEGO\u00AE MINDSTORMS\u00AE"] = "legomindstorms"
            DOC_MAP["Experimental"] = "experimental"
            DOC_MAP["Extension"] = "extension"
        }
    }

    /**
     * Returns the display name of this category, as used on the Designer palette, such
     * as "Not ready for prime time".  To get the enum name (such as "EXPERIMENTAL"),
     * use [.toString].
     *
     * @return the display name of this category
     */
    fun getName() = value

    /**
     * Returns a version of the name of this category consisting of only lower-case
     * letters, meant for use in a URL.  For example, for the category with the enum
     * name "EXPERIMENTAL" and display name "Not ready for prime time", this returns
     * "experimental".
     *
     * @return a name for this category consisting of only lower-case letters
     */
    fun getDocName() = DOC_MAP[name]
}
