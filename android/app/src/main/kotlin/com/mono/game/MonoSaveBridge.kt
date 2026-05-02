package com.mono.game

import android.content.Context
import android.webkit.JavascriptInterface

/**
 * Native bridge for Mono's local save API. Exposed to the WebView as
 * `MonoSaveNative`; the JS side (runtime/save.js WebBackend) auto-routes
 * through this when present, otherwise falls back to localStorage.
 *
 * Storage layout: one SharedPreferences file ("mono_save") whose entries
 * are cartId → JSON bucket string. One entry per cart.
 */
class MonoSaveBridge(context: Context) {
    private val prefs = context.applicationContext.getSharedPreferences(
        "mono_save", Context.MODE_PRIVATE
    )

    /** Returns the stored JSON for `cartId`, or "" if nothing is stored. */
    @JavascriptInterface
    fun read(cartId: String): String {
        return prefs.getString(cartId, "") ?: ""
    }

    /** Synchronously writes `json` under `cartId`. Returns whether commit succeeded. */
    @JavascriptInterface
    fun write(cartId: String, json: String): Boolean {
        return prefs.edit().putString(cartId, json).commit()
    }

    /** Removes `cartId`'s entry. */
    @JavascriptInterface
    fun clear(cartId: String) {
        prefs.edit().remove(cartId).apply()
    }
}
