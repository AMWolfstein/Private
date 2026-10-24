package com.zarz.spotiflac

/** Keep optional native loaders/JNI failures inside the existing playback error path. */
internal inline fun <T> nativePlaybackCall(block: () -> T): T = try {
    block()
} catch (error: LinkageError) {
    throw IllegalStateException("Native audio unavailable", error)
}
