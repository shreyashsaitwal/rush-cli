package io.github.shreyashsaitwal.rush

import java.util.regex.Pattern
import javax.annotation.processing.Messager
import javax.lang.model.element.Element
import javax.lang.model.element.TypeElement
import javax.lang.model.type.DeclaredType
import javax.lang.model.type.TypeKind
import javax.lang.model.type.TypeMirror
import javax.tools.Diagnostic

class Utils {
    companion object {

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

        /**
         * Returns a YAIL type from given [type].
         */
        fun yailTypeOf(
            element: Element,
            type: TypeMirror,
            isHelper: Boolean,
            messager: Messager,
            allowBoxedTypes: Boolean = false,
        ): String? {
            val kind = type.kind

            val numTypes = setOf(
                TypeKind.BYTE,
                TypeKind.INT,
                TypeKind.SHORT, TypeKind.LONG,
                TypeKind.FLOAT, TypeKind.DOUBLE,
            )
            if (kind in numTypes) {
                return "number"
            }

            if (kind == TypeKind.BOOLEAN) {
                return "boolean"
            }

            if (kind == TypeKind.CHAR) {
                return "char"
            }

            if (kind == TypeKind.DECLARED) {
                val typeElement = (type as DeclaredType).asElement() as TypeElement
                val typeFqcn = typeElement.qualifiedName.toString()

                val boxedTypes = mapOf(
                    "java.lang.Boolean" to "boolean",
                    "java.lang.Byte" to "byte",
                    "java.lang.Char" to "char",
                    "java.lang.Short" to "short",
                    "java.lang.Integer" to "int",
                    "java.lang.Long" to "long",
                    "java.lang.Float" to "float",
                    "java.lang.Double" to "double",
                )
                if (allowBoxedTypes && boxedTypes.containsKey(type.toString())) {
                    return boxedTypes[type.toString()]!!
                }

                val runtimeFqcn = "com.google.appinventor.components.runtime"
                when (typeFqcn) {
                    "java.lang.Object" -> return "any"
                    "java.lang.String" -> return "text"
                    "java.util.Calendar" -> return "InstantInTime"
                    "java.util.List" -> return "list"
                    "$runtimeFqcn.util.YailList" -> return "list"
                    "$runtimeFqcn.util.YailObject" -> return "yailobject"
                    "$runtimeFqcn.util.YailDictionary" -> return "dictionary"
                    "$runtimeFqcn.Component" -> return "component"
                    "$runtimeFqcn.util.Continuation" -> return "continuation"
                }

                // Every App Inventor component implements the `Component` interface
                val implementsComponent = typeElement.interfaces.any {
                    val interfaceTypeElement = (it as DeclaredType).asElement() as TypeElement
                    interfaceTypeElement.qualifiedName.toString() == "$runtimeFqcn.Component"
                }
                if (implementsComponent) {
                    return "component"
                }

                if (isHelper) {
                    return "${typeFqcn}Enum"
                }
            }

            messager.printMessage(Diagnostic.Kind.ERROR, "Cannot convert Java type to YAIL type", element)
            return null
        }
    }
}
