package com.amwolfstein.sistrum

import com.antonkarpenko.ffmpegkit.FFmpegKit
import com.antonkarpenko.ffmpegkit.ReturnCode

/** Encode local test audio without depending on the removed download engine. */
internal object LocalAudioFixtures {
    fun runFFmpegArguments(arguments: Array<String>): Pair<Boolean, String> {
        val session = FFmpegKit.executeWithArguments(arguments)
        return ReturnCode.isSuccess(session.returnCode) to (session.allLogsAsString ?: "")
    }
}
