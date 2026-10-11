package com.example.gamma

import android.util.Log
import androidx.media3.exoplayer.ExoPlayer
import com.google.appinventor.components.annotations.Extension
import com.google.appinventor.components.annotations.SimpleFunction
import com.google.appinventor.components.runtime.AndroidNonvisibleComponent
import com.google.appinventor.components.runtime.ComponentContainer
import com.google.common.collect.ImmutableList
import com.google.gson.Gson
import com.google.gson.annotations.SerializedName

class Track(
    @SerializedName("title") val title: String,
    @SerializedName("groups") val groups: Int,
)

@Extension(description = "Uses Media3, Guava types and Gson.", icon = "icon.png")
class Gamma(container: ComponentContainer) : AndroidNonvisibleComponent(container.`$form`()) {

    private val player = ExoPlayer.Builder(container.`$context`()).build()

    init {
        val groups: ImmutableList<*> = player.currentTracks.groups
        val json = Gson().toJson(Track("gamma", groups.size))
        val parsed = Gson().fromJson(json, Track::class.java)
        Log.i("RushE2E", "Gamma ready: $json ${parsed.title}/${parsed.groups}")
    }

    @SimpleFunction(description = "Returns the number of track groups.")
    fun TrackGroups(): Int = player.currentTracks.groups.size
}
