package com.google.appinventor.components.common

/**
 * Contains constants related to the description of Simple components.
 */
object ComponentDescriptorConstants {
    // shared constants between ComponentListGenerator.java and Compiler.java
    const val ARMEABI_V7A_SUFFIX = "-v7a"
    const val ARM64_V8A_SUFFIX = "-v8a"
    const val X86_64_SUFFIX = "-x8a"
    const val ASSET_DIRECTORY = "component"
    const val ASSETS_TARGET = "assets"
    const val ACTIVITIES_TARGET = "activities"
    const val METADATA_TARGET = "metadata"
    const val ACTIVITY_METADATA_TARGET = "activityMetadata"
    const val LIBRARIES_TARGET = "libraries"
    const val NATIVE_TARGET = "native"
    const val PERMISSIONS_TARGET = "permissions"
    const val BROADCAST_RECEIVERS_TARGET = "broadcastReceivers"
    const val SERVICES_TARGET = "services"
    const val CONTENT_PROVIDERS_TARGET = "contentProviders"
    const val ANDROIDMINSDK_TARGET = "androidMinSdk"
    const val CONDITIONALS_TARGET = "conditionals"

    // TODO(Will): Remove the following target once the deprecated
    //             @SimpleBroadcastReceiver annotation is removed. It should
    //             should remain for the time being because otherwise we'll break
    //             extensions currently using @SimpleBroadcastReceiver.
    const val BROADCAST_RECEIVER_TARGET = "broadcastReceiver"
}
