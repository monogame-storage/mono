package com.mono.game

import androidx.compose.runtime.Composable
import androidx.compose.runtime.mutableStateOf

// No-op billing configuration (no in-app purchases by default).

object BillingConfig {
    val adRemoved = mutableStateOf(false)
    fun initialize(context: android.content.Context) {}
    fun launchPurchase(activity: android.app.Activity) {}
}

@Composable
fun RemoveAdsButton() {}
