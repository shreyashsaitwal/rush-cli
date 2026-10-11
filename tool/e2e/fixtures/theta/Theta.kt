package com.example.theta

import android.util.Log
import androidx.core.os.bundleOf
import androidx.media3.exoplayer.ExoPlayer
import com.google.appinventor.components.annotations.Extension
import com.google.appinventor.components.annotations.SimpleFunction
import com.google.appinventor.components.runtime.AndroidNonvisibleComponent
import com.google.appinventor.components.runtime.ComponentContainer

@Extension(description = "Uses Media3 and core-ktx.", icon = "icon.png")
class Theta(container: ComponentContainer) : AndroidNonvisibleComponent(container.`$form`()) {

    private val player = ExoPlayer.Builder(container.`$context`()).build()

    init {
        val state = bundleOf("groups" to player.currentTracks.groups.size)
        Log.i("RushE2E", "Theta ready: ${state.getInt("groups")}")
    }

    @SimpleFunction(description = "Returns the number of track groups.")
    fun TrackGroups(): Int = player.currentTracks.groups.size
}
