package com.zarz.spotiflac

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Test

class ErrorJsonTest {
    @Test fun escapesQuotesBackslashesAndControlCharacters() {
        val message = "bad \"cover\" \\ path\nnext\tline"

        val parsed = JSONObject(errorJson(message))

        assertFalse(parsed.getBoolean("success"))
        assertEquals(message, parsed.getString("error"))
        assertEquals(message, parsed.getString("message"))
    }
}
