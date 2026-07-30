import java.security.MessageDigest

plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.kotlin.serialization)
    alias(libs.plugins.ksp)
}

android {
    namespace = "com.rivendell.stayword"
    compileSdk = 36
    compileSdkMinor = 1

    defaultConfig {
        applicationId = "com.rivendell.stayword"
        minSdk = 31
        targetSdk = 36
        versionCode = 1
        versionName = "1.0.0"
        testInstrumentationRunner = "com.rivendell.stayword.StayWordTestRunner"
        vectorDrawables.useSupportLibrary = true
    }

    buildTypes {
        debug {
            isMinifyEnabled = false
        }
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
            ndk.abiFilters += "arm64-v8a"
        }
    }

    buildFeatures {
        compose = true
        buildConfig = true
    }

    androidResources {
        noCompress += listOf("onnx", "litertlm", "txt")
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    packaging {
        jniLibs.useLegacyPackaging = true
        resources.excludes += setOf(
            "META-INF/DEPENDENCIES",
            "META-INF/LICENSE*",
            "META-INF/NOTICE*",
        )
    }

    testOptions.unitTests.isIncludeAndroidResources = true
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

ksp {
    arg("room.schemaLocation", "$projectDir/schemas")
    arg("room.generateKotlin", "true")
}

dependencies {
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.activity.compose)
    implementation(libs.androidx.lifecycle.runtime.compose)
    implementation(libs.androidx.lifecycle.viewmodel.compose)
    implementation(libs.androidx.lifecycle.process)

    implementation(platform(libs.androidx.compose.bom))
    implementation(libs.androidx.compose.ui)
    implementation(libs.androidx.compose.ui.tooling.preview)
    implementation(libs.androidx.compose.material3)
    implementation(libs.androidx.compose.icons)
    implementation(libs.androidx.material3.adaptive)

    implementation(libs.androidx.navigation3.runtime)
    implementation(libs.androidx.navigation3.ui)
    implementation(libs.kotlinx.serialization.json)

    implementation(libs.androidx.room3.runtime)
    implementation(libs.androidx.sqlite.framework)
    ksp(libs.androidx.room3.compiler)
    implementation(libs.androidx.work.runtime)

    implementation(libs.androidx.media3.exoplayer)
    implementation(libs.androidx.media3.session)
    implementation(libs.kotlinx.coroutines.android)

    implementation(libs.mlkit.genai.prompt)
    implementation(libs.litertlm.android)
    implementation(files("libs/sherpa-onnx-1.13.2.aar"))

    testImplementation(libs.junit4)
    testImplementation(libs.kotlinx.coroutines.test)
    testImplementation(libs.androidx.room3.testing)
    androidTestImplementation(libs.androidx.junit)
    androidTestImplementation(libs.androidx.test.core)
    androidTestImplementation(libs.androidx.test.runner)
    androidTestImplementation(libs.androidx.espresso.core)
    androidTestImplementation(platform(libs.androidx.compose.bom))
    androidTestImplementation(libs.androidx.compose.ui.test.junit4)
    debugImplementation(libs.androidx.compose.ui.tooling)
    debugImplementation(libs.androidx.compose.ui.test.manifest)
}

tasks.register("verifyModelAssets") {
    group = "verification"
    description = "Verifies the bundled offline model manifest and files."
    doLast {
        val manifest = file("src/main/assets/models/manifest.json")
        check(manifest.isFile) { "Missing model manifest: ${manifest.path}" }
        val manifestText = manifest.readText()
        val entryPattern = Regex(
            """\{\s*"path"\s*:\s*"([^"]+)"\s*,\s*"bytes"\s*:\s*(\d+)\s*,\s*"sha256"\s*:\s*"([a-f0-9]{64})"[^}]*}""",
        )
        val entries = entryPattern.findAll(manifestText).associate { match ->
            match.groupValues[1] to (match.groupValues[2].toLong() to match.groupValues[3])
        }
        val required = listOf(
            "vad/silero_vad.onnx",
            "pyannote/model.int8.onnx",
            "speaker/3dspeaker.onnx",
            "sensevoice/model.int8.onnx",
            "sensevoice/tokens.txt",
            "summary/qwen3_0.6b_nothink_q4_block32_ekv1280.litertlm",
        )
        check(entries.keys == required.toSet()) {
            "Model manifest entries do not match the required bundled models"
        }
        required.forEach { relative ->
            val model = file("src/main/assets/models/$relative")
            check(model.isFile) {
                "Missing bundled model: $relative"
            }
            val (expectedBytes, expectedSha256) = checkNotNull(entries[relative])
            check(model.length() == expectedBytes) {
                "Model size mismatch: $relative"
            }
            val digest = MessageDigest.getInstance("SHA-256")
            model.inputStream().buffered().use { input ->
                val buffer = ByteArray(DEFAULT_BUFFER_SIZE * 4)
                while (true) {
                    val count = input.read(buffer)
                    if (count < 0) break
                    digest.update(buffer, 0, count)
                }
            }
            val actualSha256 = digest.digest().joinToString("") { byte: Byte -> "%02x".format(byte) }
            check(actualSha256 == expectedSha256) {
                "Model SHA-256 mismatch: $relative"
            }
        }
    }
}
