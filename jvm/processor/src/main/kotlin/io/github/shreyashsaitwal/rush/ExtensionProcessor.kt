package io.github.shreyashsaitwal.rush

import com.google.appinventor.components.annotations.Extension
import com.google.appinventor.components.annotations.SimpleEvent
import com.google.appinventor.components.annotations.SimpleFunction
import com.google.appinventor.components.annotations.SimpleProperty
import com.google.auto.service.AutoService
import io.github.shreyashsaitwal.rush.block.DesignerProperty
import io.github.shreyashsaitwal.rush.block.Event
import io.github.shreyashsaitwal.rush.block.Function
import io.github.shreyashsaitwal.rush.block.Property
import io.github.shreyashsaitwal.rush.block.loadHelpersFrom
import javax.annotation.processing.*
import javax.lang.model.SourceVersion
import javax.lang.model.element.Element
import javax.lang.model.element.ExecutableElement
import javax.lang.model.element.TypeElement
import javax.lang.model.util.Elements
import javax.tools.Diagnostic.Kind
import com.google.appinventor.components.annotations.DesignerProperty as DesignerPropertyAnnotation

@AutoService(Processor::class)
@SupportedAnnotationTypes(
    "com.google.appinventor.components.annotations.Extension",
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

    override fun getSupportedSourceVersion(): SourceVersion = SourceVersion.latestSupported()

    override fun getSupportedOptions(): Set<String> = setOf(ProcessorOptions.OPTIONS)

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

        val options = try {
            ProcessorOptions(processingEnv.options)
        } catch (e: ProcessingError) {
            messager.printMessage(Kind.ERROR, e.message)
            return false
        }
        loadHelpersFrom(options.helperClasspath)

        val elements = roundEnv.getElementsAnnotatedWith(Extension::class.java)
        val extensions = elements.map { processExtensionElement(it) }
        val packages = extensions.map { it.fqcn.substringBeforeLast('.') }.distinct()
        if (packages.size > 1) {
            messager.printMessage(
                Kind.ERROR,
                "All extensions in a project must be in the same package, found: ${packages.joinToString()}"
            )
            return false
        }

        val generator = InfoFilesGenerator(extensions, options, elementUtils, messager)
        try {
            generator.generateComponentsJson()
            generator.generateBuildInfoJson()
        } catch (e: ProcessingError) {
            messager.printMessage(Kind.ERROR, e.message)
        } catch (e: Throwable) {
            messager.printMessage(Kind.ERROR, e.message + "\n" + e.stackTraceToString())
        }

        return false
    }

    private fun processExtensionElement(element: Element): ExtensionModel {
        val events = element.enclosedElements
            .filter { it.getAnnotation(SimpleEvent::class.java) != null }
            .map { Event(it as ExecutableElement, messager, elementUtils) }

        val functions = element.enclosedElements
            .filter { it.getAnnotation(SimpleFunction::class.java) != null }
            .map { Function(it as ExecutableElement, messager, elementUtils) }

        val properties = mutableListOf<Property>()
        element.enclosedElements
            .filter { it.getAnnotation(SimpleProperty::class.java) != null }
            .forEach { Property(it as ExecutableElement, messager, elementUtils, properties) }

        val designerProperties = element.enclosedElements
            .filter { it.getAnnotation(DesignerPropertyAnnotation::class.java) != null }
            .map { DesignerProperty(it as ExecutableElement, messager, elementUtils, properties) }

        val packageName = elementUtils.getPackageOf(element).qualifiedName.toString()
        val fqcn = "$packageName.${element.simpleName}"

        return ExtensionModel(
            element,
            fqcn,
            events,
            functions,
            properties,
            designerProperties
        )
    }
}
