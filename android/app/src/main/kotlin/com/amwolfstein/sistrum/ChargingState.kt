package com.amwolfstein.sistrum

import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.BatteryManager

internal object ChargingState {
    fun externallyPowered(plugged: Int): Boolean = plugged > 0
    fun read(context: Context): Boolean {
        val battery = context.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        return externallyPowered(battery?.getIntExtra(BatteryManager.EXTRA_PLUGGED, 0) ?: 0)
    }
}
