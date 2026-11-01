package com.amwolfstein.sistrum

import android.content.Context
import android.net.Uri
import android.os.ParcelFileDescriptor
import androidx.documentfile.provider.DocumentFile
import java.util.UUID

/** Process-owned descriptors survive Activity recreation/finish; Dart closes
 * each token after preparation. Only engine teardown closes abandoned leases. */
internal object PlaybackFileLeases {
    private const val MAX_LEASES = 8
    private data class Lease(val owner: Any, val descriptor: ParcelFileDescriptor)
    private val leases = mutableMapOf<String, Lease>()
    private var currentOwner: Any? = null

    fun attachOwner(owner: Any) = synchronized(leases) { currentOwner = owner }
    fun retireOwner(owner: Any) = synchronized(leases) { if (currentOwner === owner) currentOwner = null }

    fun open(context: Context, source: String, owner: Any): Map<String, String>? {
        if (!source.startsWith("content://")) return null
        val uri = Uri.parse(source)
        val descriptor = context.contentResolver.openFileDescriptor(uri, "r") ?: return null
        try {
            if (!isSeekableSafDescriptor(descriptor)) { descriptor.close(); return null }
            // Query before transferring ownership: a failed query must not leak a lease.
            val name = runCatching { DocumentFile.fromSingleUri(context, uri)?.name }.getOrNull()
                ?: uri.lastPathSegment ?: "audio"
            val token = UUID.randomUUID().toString()
            val accepted = synchronized(leases) {
                if (currentOwner !== owner || leases.size >= MAX_LEASES) false else { leases[token] = Lease(owner, descriptor); true }
            }
            if (!accepted) { descriptor.close(); return null }
            return mapOf("token" to token, "path" to "/proc/self/fd/${descriptor.fd}", "display_name" to name)
        } catch (error: Exception) {
            runCatching { descriptor.close() }
            throw error
        }
    }

    fun close(token: String) {
        val descriptor = synchronized(leases) { leases.remove(token)?.descriptor } ?: return
        runCatching { descriptor.close() }
    }

    fun closeOwner(owner: Any) {
        val descriptors = synchronized(leases) {
            val owned = leases.filterValues { it.owner === owner }
            owned.keys.forEach { leases.remove(it) }
            owned.values.map { it.descriptor }
        }
        descriptors.forEach { runCatching { it.close() } }
    }
}
