plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.plugin.compose")
}

android {
    namespace = "com.mono.game"
    compileSdk = 36

    defaultConfig {
        applicationId = "com.mono.game"
        minSdk = 24
        targetSdk = 36
        versionCode = 1
        versionName = "1.0.0"
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    buildFeatures {
        compose = true
    }
}

// --- Configuration ---
// cart/ must contain main.lua and .mono/engine.js (deployed by Mono editor)
val cartDir = file("${rootProject.projectDir}/cart")
val assetsDir = file("src/main/assets")
val cartAssetsDir = file("${assetsDir}/cart")

// --- syncCart: cart/ + engine → assets/cart/ ---
val syncCart = tasks.register("syncCart") {
    inputs.dir(cartDir)
    inputs.file("templates/index.html")
    outputs.dir(cartAssetsDir)
    outputs.upToDateWhen { false }

    doLast {
        if (cartAssetsDir.exists()) cartAssetsDir.deleteRecursively()
        cartAssetsDir.mkdirs()

        // Copy game files from cart/ (exclude .mono/ and .gitignore)
        cartDir.listFiles()?.filter { it.name != ".mono" && it.name != ".gitignore" }?.forEach { src ->
            val dst = file("${cartAssetsDir}/${src.name}")
            if (src.isDirectory) src.copyRecursively(dst, overwrite = true)
            else src.copyTo(dst, overwrite = true)
        }
        logger.lifecycle("syncCart: game files copied from cart/")

        // engine/ directory
        val engineDir = file("${cartAssetsDir}/engine")
        engineDir.mkdirs()

        // Patch engine.js for offline local loading (from cart/.mono/engine.js)
        val engineSrc = file("${cartDir}/.mono/engine.js")
        var content = engineSrc.readText()
        content = content.replace(
            "var Mono = (() => {\n  \"use strict\";\n\n  const W = 160",
            "var Mono = (() => {\n  \"use strict\";\n\n" +
            "  const _scriptEl = document.currentScript || document.querySelector('script[src*=\"engine.js\"]');\n" +
            "  const _engineBase = _scriptEl ? new URL(\".\", _scriptEl.src).href : new URL(\".\", location.href).href;\n\n" +
            "  const W = 160"
        )
        content = content.replace(
            "const { LuaFactory } = await import(\"https://cdn.jsdelivr.net/npm/wasmoon@1.16.0/+esm\");",
            "const { LuaFactory } = await import(_engineBase + \"wasmoon.esm.js\");"
        )
        content = content.replace(
            "const factory = new LuaFactory();",
            "const factory = new LuaFactory(_engineBase + \"glue.wasm\");"
        )
        file("${engineDir}/engine.js").writeText(content)
        logger.lifecycle("syncCart: engine.js patched")

        // console-gamepad.js (from cart/.mono/)
        file("${cartDir}/.mono/console-gamepad.js")
            .copyTo(file("${engineDir}/console-gamepad.js"), overwrite = true)
        logger.lifecycle("syncCart: console-gamepad.js copied")

        // Download wasmoon (cached)
        val cache = file("${rootProject.projectDir}/.cache/wasmoon").apply { mkdirs() }
        fun cached(name: String, url: String): File {
            val f = file("${cache}/${name}")
            if (!f.exists()) {
                ProcessBuilder("curl", "-sL", "-o", f.absolutePath, url).start().waitFor()
                logger.lifecycle("syncCart: ${name} downloaded")
            }
            return f
        }
        cached("wasmoon.esm.js", "https://cdn.jsdelivr.net/npm/wasmoon@1.16.0/+esm")
            .copyTo(file("${engineDir}/wasmoon.esm.js"))
        cached("glue.wasm", "https://unpkg.com/wasmoon@1.16.0/dist/glue.wasm")
            .copyTo(file("${engineDir}/glue.wasm"))

        // index.html template
        file("templates/index.html")
            .copyTo(file("${cartAssetsDir}/index.html"), overwrite = true)
        logger.lifecycle("syncCart: build complete")
    }
}

tasks.matching { it.name.startsWith("merge") && it.name.endsWith("Assets") }.configureEach {
    dependsOn(syncCart)
}

dependencies {
    implementation(platform("androidx.compose:compose-bom:2026.03.00"))
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.activity:activity-compose:1.13.0")
    implementation("androidx.core:core-ktx:1.18.0")
    implementation("androidx.webkit:webkit:1.15.0")
}
