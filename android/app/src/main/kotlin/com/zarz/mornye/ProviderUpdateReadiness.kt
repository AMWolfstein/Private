package com.zarz.mornye

/** Complete policy setup before optional update I/O can be scheduled. */
internal fun <T> configureBackendAndStartUpdates(
    owner: T,
    configure: (T) -> Unit,
    startUpdates: (T) -> Unit,
    updateFailure: (T, Exception) -> Unit,
    dispose: (T) -> Unit,
) {
    try {
        configure(owner)
    } catch (error: Exception) {
        try {
            dispose(owner)
        } catch (cleanup: Exception) {
            error.addSuppressed(cleanup)
        }
        throw error
    }
    try {
        startUpdates(owner)
    } catch (error: Exception) {
        // Optional configuration updates must not prevent local playback.
        try {
            updateFailure(owner, error)
        } catch (_: Exception) {
            // Reporting is best effort; the initialized owner remains usable.
        }
    }
}
