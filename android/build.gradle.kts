group = "com.manishpanday.interactive_keyboard_dismiss"
version = "0.1.0"

buildscript {
    val kotlinVersion = "2.2.20"
    repositories {
        google()
        mavenCentral()
    }

    dependencies {
        classpath("com.android.tools.build:gradle:8.11.1")
        classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:$kotlinVersion")
    }
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// The Kotlin Gradle Plugin is still applied here because AGP's built-in Kotlin
// support (`android.builtInKotlin`) only exists in AGP 9 / Flutter 3.44+, and
// this plugin supports Flutter 3.35+. Once the minimum moves to Flutter 3.44,
// drop the `kotlin-android` plugin and the KGP classpath above; the
// `kotlin { compilerOptions { … } }` block below is already the form built-in
// Kotlin expects.
// https://docs.flutter.dev/release/breaking-changes/migrate-to-built-in-kotlin/for-plugin-authors
plugins {
    id("com.android.library")
    id("kotlin-android")
}

android {
    namespace = "com.manishpanday.interactive_keyboard_dismiss"

    compileSdk = 36

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    sourceSets {
        getByName("main") {
            java.srcDirs("src/main/kotlin")
        }
    }

    defaultConfig {
        minSdk = 24
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    implementation("androidx.core:core-ktx:1.13.1")
}
