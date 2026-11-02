package com.amwolfstein.sistrum

import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities

/** Reports the active network as `wifi`, `cellular`, `other` or `none`. */
object NetworkKind {
    fun read(context: Context): String {
        return try {
            val manager = context.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
                ?: return "none"
            val network = manager.activeNetwork ?: return "none"
            val capabilities = manager.getNetworkCapabilities(network) ?: return "none"
            if (!capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)) return "none"
            when {
                capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> "wifi"
                capabilities.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> "cellular"
                else -> "other"
            }
        } catch (error: SecurityException) {
            "none"
        }
    }
}
