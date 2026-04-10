# Mono Android wrapper ProGuard rules

# --- androidx.work / androidx.room ---
# Google Mobile Ads pulls in WorkManager (androidx.work), which uses Room
# (WorkDatabase) internally. R8 can obfuscate the Room-generated classes and
# break reflection at runtime:
#   java.lang.RuntimeException: Failed to create an instance of androidx.work.impl.WorkDatabase
-keep class androidx.work.** { *; }
-keep class androidx.work.impl.** { *; }
-keep class * extends androidx.work.ListenableWorker { *; }
-keep class * extends androidx.room.RoomDatabase { *; }
-keep class * extends androidx.room.RoomOpenHelper { *; }
-keepclassmembers class * {
    @androidx.room.* <methods>;
    @androidx.room.* <fields>;
}
-dontwarn androidx.room.paging.**

# --- Google Mobile Ads ---
# The SDK uses reflection and dynamic class loading.
-keep class com.google.android.gms.ads.** { *; }
-keep class com.google.android.gms.internal.ads.** { *; }
-dontwarn com.google.android.gms.ads.**

# --- Google Play Billing ---
-keep class com.android.billingclient.api.** { *; }
-dontwarn com.android.billingclient.api.**

# --- WebView JavaScript interface (Mono engine bridge) ---
# The Lua engine bridges through a WebView JS interface; keep any @JavascriptInterface
# methods from being stripped.
-keepclassmembers class * {
    @android.webkit.JavascriptInterface <methods>;
}

# --- AndroidX lifecycle ---
-keep class androidx.lifecycle.DefaultLifecycleObserver
