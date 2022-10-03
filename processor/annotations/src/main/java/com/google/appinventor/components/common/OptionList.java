package com.google.appinventor.components.common;

/**
 * A marker interface for defining option list helper blocks via the Java scripting language. This can be expanded later
 * if we want to get more information out of option list definitions.
 */
public interface OptionList<T> {
    /**
     * Returns the underlying value of the option.
     *
     * @return the underlying value of the option
     */
    T toUnderlyingValue();
}