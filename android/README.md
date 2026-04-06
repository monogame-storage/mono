# Mono Android Wrapper

Generic Android wrapper for packaging any Mono game as an APK.

## Quick Start

1. Copy this template to a new project folder, then deploy your game from Mono editor into `cart/`:
   ```
   my-game-android/
     cart/
       .mono/
         engine.js       # deployed by editor
         VERSION
       main.lua          # entry point (required)
       scenes/           # optional scene files
       ...
   ```

2. Customize your app in `app/src/main/res/values/strings.xml`:
   ```xml
   <string name="app_name">My Game</string>
   ```

3. Update `app/build.gradle.kts` if needed:
   ```kotlin
   applicationId = "com.example.mygame"
   ```

4. Build:
   ```bash
   ./gradlew assembleDebug
   ```

The build task (`syncCart`) automatically:
- Copies game files from `cart/` to assets
- Patches `engine.js` for offline local loading
- Bundles `console-gamepad.js` (virtual touch gamepad)
- Downloads and caches wasmoon (Lua WASM runtime)

## Structure

```
my-game-android/
  cart/                    # YOUR GAME (deployed from editor)
    .mono/engine.js        # engine (auto-patched at build)
    main.lua
  app/
    src/main/
      java/.../MainActivity.kt   # WebView host (generic)
      assets/cart/                # GENERATED at build time
    templates/
      index.html                  # HTML shell template
    build.gradle.kts              # syncCart task + deps
  build.gradle.kts                # Root plugins
  settings.gradle.kts             # Project config
```

## Requirements

- Android Studio or Gradle with Android SDK
- Min SDK 24 (Android 7.0)
- Target SDK 36

## How It Works

The app is a single-activity Android app using Jetpack Compose. `MainActivity` hosts a `WebView` that loads the Mono engine + your Lua game from local assets. The virtual gamepad (`console-gamepad.js`) provides touch D-pad and A/B/START/SELECT buttons. Hardware Bluetooth/USB gamepads are also supported via the Web Gamepad API.
