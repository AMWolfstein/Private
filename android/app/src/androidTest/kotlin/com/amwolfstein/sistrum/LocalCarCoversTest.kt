package com.amwolfstein.sistrum

import android.graphics.Bitmap
import android.net.Uri
import android.os.ParcelFileDescriptor
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import org.junit.Test
import org.junit.runner.RunWith
import org.junit.Assert.*

/** Requires a device; validates real provider access and OS descriptor lifetime. */
@RunWith(AndroidJUnit4::class)
class LocalCarCoversTest {
    private fun withCover(action: (android.content.Context, Uri) -> Unit) {
        val app = InstrumentationRegistry.getInstrumentation().targetContext
        val directory = File(app.filesDir, "library_covers").also { it.mkdirs() }
        val cover = File.createTempFile("car_provider_test_", ".jpg", directory)
        val bitmap = Bitmap.createBitmap(2, 2, Bitmap.Config.ARGB_8888)
        try {
            cover.outputStream().use { bitmap.compress(Bitmap.CompressFormat.JPEG, 80, it) }
            val uri = Uri.Builder().scheme("content").authority("${app.packageName}.covers")
                .appendPath("library_covers").appendPath(cover.name).build()
            action(app, uri)
        } finally { bitmap.recycle(); cover.delete() }
    }

    @Test fun coversAreReadableButNeverWritableOrListable() = withCover { app, uri ->
        assertEquals("image/jpeg", app.contentResolver.getType(uri))
        app.contentResolver.openInputStream(uri)!!.use { assertEquals(255, it.read()) }
        assertNull(app.contentResolver.query(uri, null, null, null, null))
        for (mode in listOf("w", "rw", "rwt", "wa")) {
            try {
                app.contentResolver.openFileDescriptor(uri, mode)?.close()
                fail("Writable cover mode accepted: $mode")
            } catch (_: SecurityException) { }
        }
        try { app.contentResolver.delete(uri, null, null); fail("Delete accepted") }
        catch (_: UnsupportedOperationException) { }
    }

    @Test fun retiringAnOldEngineCannotCloseANewEnginesLease() = withCover { app, uri ->
        val first = Any()
        val next = Any()
        PlaybackFileLeases.attachOwner(first)
        val a = PlaybackFileLeases.open(app, uri.toString(), first)!!
        try {
            PlaybackFileLeases.attachOwner(next)
            val b = PlaybackFileLeases.open(app, uri.toString(), next)!!
            try {
                PlaybackFileLeases.retireOwner(first)
                PlaybackFileLeases.closeOwner(first)
                ParcelFileDescriptor.fromFd(b.getValue("path").substringAfterLast('/').toInt()).use {
                    assertTrue(it.fileDescriptor.valid())
                }
                assertNull(PlaybackFileLeases.open(app, uri.toString(), first))
            } finally { PlaybackFileLeases.close(b.getValue("token")) }
        } finally {
            PlaybackFileLeases.close(a.getValue("token"))
            PlaybackFileLeases.retireOwner(next)
            PlaybackFileLeases.closeOwner(next)
        }
    }
}
