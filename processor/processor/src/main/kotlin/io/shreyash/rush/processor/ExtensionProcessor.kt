package io.shreyash.rush.processor

import com.google.appinventor.components.annotations.ExtensionComponent
import com.google.appinventor.components.annotations.SimpleEvent
import com.google.appinventor.components.annotations.SimpleFunction
import com.google.appinventor.components.annotations.SimpleProperty
import com.google.auto.service.AutoService
import io.shreyash.rush.processor.block.DesignerProperty
import io.shreyash.rush.processor.block.Event
import io.shreyash.rush.processor.block.Function
import io.shreyash.rush.processor.block.Property
import io.shreyash.rush.processor.model.Extension
import javax.annotation.processing.*
import javax.lang.model.SourceVersion
import javax.lang.model.element.Element
import javax.lang.model.element.ExecutableElement
import javax.lang.model.element.Modifier
import javax.lang.model.element.TypeElement
import javax.lang.model.util.Elements
import javax.tools.Diagnostic

@AutoService(Processor::class)
@SupportedSourceVersion(SourceVersion.RELEASE_8)
@SupportedAnnotationTypes(
    "com.google.appinventor.components.annotations.ExtensionComponent",
    "com.google.appinventor.components.annotations.SimpleEvent",
    "com.google.appinventor.components.annotations.SimpleFunction",
    "com.google.appinventor.components.annotations.SimpleProperty",
    "com.google.appinventor.components.annotations.DesignerProperty",
    "com.google.appinventor.components.annotations.Asset",
    "com.google.appinventor.components.annotations.Options",
    "com.google.appinventor.components.common.Default",
)
class ExtensionProcessor : AbstractProcessor() {
    private var isFirstRound = true

    private lateinit var messager: Messager
    private lateinit var elementUtils: Elements

    @Synchronized
    override fun init(processingEnv: ProcessingEnvironment) {
        super.init(processingEnv)
        messager = processingEnv.messager
        elementUtils = processingEnv.elementUtils
    }

    override fun process(annotations: Set<TypeElement?>, roundEnv: RoundEnvironment): Boolean {
        if (!isFirstRound) {
            return true
        }
        isFirstRound = false

        val elements = roundEnv.getElementsAnnotatedWith(ExtensionComponent::class.java)
        elements
            .groupBy { elementUtils.getPackageOf(it).qualifiedName }
            .apply {
                if (this.size > 1) {
                    val classes = this.map {
                        val sb = StringBuilder()
                        it.value.forEach { el ->
                            sb.append("  - ${it.key}.${el.simpleName}\n")
                        }
                        sb.toString()
                    }.joinToString("\n")

                    messager.printMessage(
                        Diagnostic.Kind.ERROR,
                        """
                    |Classes annotated with @Meta annotation must reside in the same package.
                    |The following classes have different packages:
                    |$classes
                    |NOTE Try moving all the above classes under the same package.
                    """.trimMargin("|")
                    )
                }
            }

        val extensions = elements.map {
            processExtensionElement(it, elementUtils)
        }
        generateInfoFiles(extensions)

        return false
    }

    private fun processExtensionElement(element: Element, elementUtils: Elements): Extension {
        // Process simple events
        val events = element.enclosedElements
            .filter { it.getAnnotation(SimpleEvent::class.java) != null && isPublic(it) }
            .map { Event(it as ExecutableElement, messager, elementUtils) }

        // Process simple functions
        val functions = element.enclosedElements
            .filter { it.getAnnotation(SimpleFunction::class.java) != null && isPublic(it) }
            .map { Function(it as ExecutableElement, messager, elementUtils) }

        // Process simple properties
        val processedProperties = mutableListOf<Property>()
        val properties = element.enclosedElements
            .filter { it.getAnnotation(SimpleProperty::class.java) != null && isPublic(it) }
            .map {
                val property = Property(it as ExecutableElement, messager, processedProperties, elementUtils)
                processedProperties.add(property)
                property
            }

        // Process designer properties
        val designerProperties = element.enclosedElements
            .filter {
                it.getAnnotation(com.google.appinventor.components.annotations.DesignerProperty::class.java) != null
                        && isPublic(it)
            }.map { DesignerProperty(it as ExecutableElement, messager, properties) }

        val packageName = elementUtils.getPackageOf(element).qualifiedName.toString()
        val fqcn = "$packageName.${element.simpleName}"

        return Extension(
            element.getAnnotation(ExtensionComponent::class.java),
            fqcn,
            events,
            functions,
            properties,
            designerProperties
        )
    }

    /** Generates the component info files (JSON). */
    private fun generateInfoFiles(extensions: List<Extension>) {
        val generator = InfoFilesGenerator(extensions)
        try {
            generator.generateComponentsJson()
            generator.generateBuildInfoJson()
        } catch (e: Throwable) {
            messager.printMessage(Diagnostic.Kind.ERROR, e.message ?: e.stackTraceToString())
        }
    }

    /** @returns `true` if [element] is a public element. */
    private fun isPublic(element: Element): Boolean {
        val isPublic = element.modifiers.contains(Modifier.PUBLIC)
        if (!isPublic) {
            messager.printMessage(
                Diagnostic.Kind.WARNING,
                "Element \"${element.simpleName}\" is private. It should be public to be visible in" +
                        " the blocks editor."
            )
        }
        return isPublic
    }
}
