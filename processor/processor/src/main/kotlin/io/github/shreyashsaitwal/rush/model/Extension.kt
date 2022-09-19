package io.github.shreyashsaitwal.rush.model

import com.google.appinventor.components.annotations.ExtensionComponent
import io.github.shreyashsaitwal.rush.block.DesignerProperty
import io.github.shreyashsaitwal.rush.block.Event
import io.github.shreyashsaitwal.rush.block.Function
import io.github.shreyashsaitwal.rush.block.Property

data class Extension(
    val extensionComponent: ExtensionComponent,
    val fqcn: String,
    val events: List<Event>,
    val functions: List<Function>,
    val properties: List<Property>,
    val designerProperties: List<DesignerProperty>,
)
