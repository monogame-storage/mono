package com.mono.game

import androidx.compose.runtime.Composable

// No-op ad configuration (no ads by default).

object AdConfig {
    val enabled = false
    fun initialize(activity: android.app.Activity) {}
}

@Composable
fun BannerAdSlot() {}
