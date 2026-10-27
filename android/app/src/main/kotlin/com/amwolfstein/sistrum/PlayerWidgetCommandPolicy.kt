package com.amwolfstein.sistrum

/** Shared boundary for broadcast and exported-activity widget commands. */
internal object PlayerWidgetCommandPolicy {
    fun isAllowed(command: String?): Boolean =
        command == "toggle" || command == "next" || command == "previous"
}
