package com.amwolfstein.sistrum

import java.io.File
import java.nio.file.Files
import org.junit.After
import org.junit.Before
import org.junit.Test
import org.junit.Assert.*

class CoverProviderFilesTest {
    private lateinit var root: File
    private lateinit var folders: Map<String, CoverProviderFiles.Folder>
    @Before fun setup() {
        root = Files.createTempDirectory("sistrum-cover-policy-").toFile().canonicalFile
        folders = CoverProviderFiles.folders(File(root, "files"), File(root, "cache"))
        folders.values.forEach { it.directory.mkdirs() }
    }
    @After fun cleanup() { root.deleteRecursively() }
    private fun file(folder: String, name: String): File = File(folders.getValue(folder).directory,name).also { it.writeBytes(byteArrayOf(-1,-40,-1)) }

    @Test fun servesOnlyTheLocalCoverDirectories() {
        assertEquals(setOf("library_covers","playlist_covers","embedded_cover_previews"),folders.keys)
        for (folder in folders.keys) {
            val image = file(folder,"cover.jpg")
            assertEquals(image,CoverProviderFiles.resolve(folders,listOf(folder,"cover.jpg")))
            assertEquals(folder to "cover.jpg",CoverProviderFiles.locate(folders,image.path))
        }
    }
    @Test fun rejectsTraversalHiddenFilesSidecarsAndNonFiles() {
        val forbidden = listOf("..",".","", ".secret.jpg", "cover.jpg.tmp", "cover.jpg.source", "../settings.jpg", "sub/picture.jpg", "zero\u0000.jpg")
        for (name in forbidden) assertNull(name,CoverProviderFiles.resolve(folders,listOf("library_covers",name)))
        File(folders.getValue("library_covers").directory,"folder.jpg").mkdirs()
        assertNull(CoverProviderFiles.resolve(folders,listOf("library_covers","folder.jpg")))
        assertNull(CoverProviderFiles.resolve(folders,listOf("library_covers","missing.jpg")))
        assertNull(CoverProviderFiles.resolve(folders,listOf("library_covers")))
        assertNull(CoverProviderFiles.resolve(folders,listOf("other","cover.jpg")))
        assertNull(CoverProviderFiles.locate(folders,"/storage/emulated/0/Music/cover.jpg"))
        assertNull(CoverProviderFiles.locate(folders,"library_covers/cover.jpg"))
    }
    @Test fun symlinksCannotEscapeTheAllowedFolder() {
        val outside = File(root,"private.jpg").also { it.writeText("secret") }
        val link = File(folders.getValue("library_covers").directory,"link.jpg")
        Files.createSymbolicLink(link.toPath(),outside.toPath())
        assertNull(CoverProviderFiles.resolve(folders,listOf("library_covers","link.jpg")))
        val other = file("playlist_covers","other.jpg")
        val cross = File(folders.getValue("library_covers").directory,"cross.jpg")
        Files.createSymbolicLink(cross.toPath(),other.toPath())
        assertNull(CoverProviderFiles.resolve(folders,listOf("library_covers","cross.jpg")))
    }
    @Test fun fileNameRulesDependOnTheActualFolder() {
        assertTrue(folders.getValue("library_covers").names("hash.image"))
        assertFalse(folders.getValue("playlist_covers").names("hash.image"))
        assertFalse(folders.getValue("embedded_cover_previews").names("hash.png"))
        assertFalse(folders.getValue("library_covers").names(".jpg"))
    }
    @Test fun recognizesImagesAndRejectsTextAndAudioHeaders() {
        fun type(vararg values: Int) = CoverProviderFiles.imageType(ByteArray(values.size) { values[it].toByte() })
        assertEquals("image/jpeg",type(255,216,255))
        assertEquals("image/png",type(137,80,78,71,13,10,26,10))
        assertEquals("image/webp",CoverProviderFiles.imageType("RIFF1234WEBP".toByteArray()))
        assertNull(CoverProviderFiles.imageType("RIFF1234WAVE".toByteArray()))
        assertNull(CoverProviderFiles.imageType("<svg>".toByteArray()))
        assertNull(CoverProviderFiles.imageType(byteArrayOf()))
        assertNull(type(255,216))
    }
}
