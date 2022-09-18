package com.google.appinventor.components.common

/**
 * A marker interface for defining option list helper blocks via the Java scripting language.
 * This can be expanded later if we want to get more information out of option list definitions.
 */
interface OptionList<T> {
    fun toUnderlyingValue(): T
}