package com.example.delta

import android.util.Log
import com.google.appinventor.components.annotations.Extension
import com.google.appinventor.components.annotations.SimpleFunction
import com.google.appinventor.components.runtime.AndroidNonvisibleComponent
import com.google.appinventor.components.runtime.ComponentContainer
import kotlin.uuid.ExperimentalUuidApi
import kotlin.uuid.Uuid

@Extension(description = "Uses an API added in Kotlin 2.0.20.", icon = "icon.png")
class Delta(container: ComponentContainer) : AndroidNonvisibleComponent(container.`$form`()) {

    @OptIn(ExperimentalUuidApi::class)
    private val id = Uuid.random().toString()

    init {
        Log.i("RushE2E", "Delta ready: $id")
    }

    @SimpleFunction(description = "Returns the random id.")
    fun Id(): String = id
}
