package com.amwolfstein.sistrum

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import java.nio.file.Files

class SafScanOutputRepairTest {
    private fun output(content: String): File {
        val file = Files.createTempFile("saf-scan-output", ".ndjson").toFile()
        file.writeText(content, Charsets.UTF_8)
        file.deleteOnExit()
        return file
    }

    @Test fun completeOutputIsKept() {
        val file = output("{\"a\":1}\n{\"b\":2}\n")
        repairSafScanOutput(file.path)
        assertEquals("{\"a\":1}\n{\"b\":2}\n", file.readText())
    }

    @Test fun interruptedRowIsDropped() {
        val file = output("{\"a\":1}\n{\"b\":2}\n{\"c\":\"unfin")
        repairSafScanOutput(file.path)
        assertEquals("{\"a\":1}\n{\"b\":2}\n", file.readText())
    }

    @Test fun outputWithoutAnyNewlineIsEmptied() {
        val file = output("{\"a\":\"interrupted before the first line ended\"")
        repairSafScanOutput(file.path)
        assertEquals("", file.readText())
    }

    @Test fun emptyOutputStaysEmpty() {
        val file = output("")
        repairSafScanOutput(file.path)
        assertEquals("", file.readText())
    }

    @Test fun missingFileIsIgnored() {
        val file = Files.createTempFile("saf-scan-missing", ".ndjson").toFile()
        assertTrue(file.delete())
        repairSafScanOutput(file.path)
    }

    @Test fun newlineBeyondOneBlockIsFound() {
        // The trailing partial row spans more than one repair block, so the
        // search has to walk backwards past it.
        val large = "x".repeat(64 * 1024)
        val partial = "y".repeat(32 * 1024)
        val file = output("$large\n$partial")
        repairSafScanOutput(file.path)
        assertEquals("$large\n", file.readText())
    }

    @Test fun completeEmptyLineAtEndStays() {
        val file = output("{\"a\":1}\n\n")
        repairSafScanOutput(file.path)
        assertEquals("{\"a\":1}\n\n", file.readText())
    }
}
