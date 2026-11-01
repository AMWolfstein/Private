package com.ryanheise.audioservice;

import android.graphics.Bitmap;
import android.support.v4.media.MediaMetadataCompat;
import androidx.test.ext.junit.runners.AndroidJUnit4;
import org.junit.Test;
import org.junit.runner.RunWith;
import static org.junit.Assert.*;

/** Real Android bitmap ownership tests; not a host/JVM substitute. */
@RunWith(AndroidJUnit4.class)
public class MediaArtworkOwnershipTest {
    @Test public void sessionAndNotificationOwnIndependentBoundedCopies() {
        Bitmap source = Bitmap.createBitmap(1024,768,Bitmap.Config.ARGB_8888);
        MediaMetadataCompat original = new MediaMetadataCompat.Builder()
                .putBitmap(MediaMetadataCompat.METADATA_KEY_ALBUM_ART,source)
                .putBitmap(MediaMetadataCompat.METADATA_KEY_DISPLAY_ICON,source).build();
        MediaMetadataCompat session = MediaArtwork.forSession(original);
        Bitmap album = session.getBitmap(MediaMetadataCompat.METADATA_KEY_ALBUM_ART);
        Bitmap icon = session.getBitmap(MediaMetadataCompat.METADATA_KEY_DISPLAY_ICON);
        Bitmap notification = MediaArtwork.copy(source,256);
        try {
            assertNotSame(source,album); assertNotSame(album,icon);
            assertTrue(album.getWidth()<=512); assertTrue(notification.getWidth()<=256);
            album.recycle();
            assertFalse(source.isRecycled()); assertFalse(icon.isRecycled());
        } finally { source.recycle(); if(!album.isRecycled())album.recycle(); icon.recycle(); notification.recycle(); }
    }
    @Test public void recycledImagesAreOmittedAndTextMetadataSurvives() {
        Bitmap source = Bitmap.createBitmap(16,16,Bitmap.Config.ARGB_8888);
        MediaMetadataCompat original = new MediaMetadataCompat.Builder()
                .putString(MediaMetadataCompat.METADATA_KEY_TITLE,"Song")
                .putBitmap(MediaMetadataCompat.METADATA_KEY_ALBUM_ART,source).build();
        source.recycle();
        MediaMetadataCompat sanitized = MediaArtwork.sanitize(original);
        assertNull(sanitized.getBitmap(MediaMetadataCompat.METADATA_KEY_ALBUM_ART));
        assertEquals("Song",sanitized.getString(MediaMetadataCompat.METADATA_KEY_TITLE));
        assertNull(MediaArtwork.copy(source,256));
    }
}
