package com.google.appinventor.components.annotations

import com.google.appinventor.components.common.OptionList
import kotlin.reflect.KClass

/**
 * Annotation to mark a parameter/return type as accepting an enum value. This should *only* be
 * used to upgrade old components. E.g., setters that currently accept concrete types like int:
 *
 * <code>@SimpleProperty
 * public void AlignHorizontal (@Options(HorizontalAlignment.class) int alignment) { }
 * </code>
 *
 * <p>New components that want to accept or return an enum should just use that enum type as the
 * parameter type. E.g:
 *
 * <code>@SimpleProperty
 * public void CurrentSeason (Season season) { }
 * </code>
 */
@Retention(AnnotationRetention.RUNTIME)
@Target(AnnotationTarget.TYPE, AnnotationTarget.VALUE_PARAMETER)
annotation class Options(
    val value: KClass<out OptionList<*>>
)
