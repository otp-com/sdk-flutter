group = "com.otp.sdk.flutter"
version = "1.0-SNAPSHOT"

buildscript {
    val kotlinVersion = "2.4.0"
    repositories {
        google()
        mavenCentral()
    }

    dependencies {
        classpath("com.android.tools.build:gradle:9.1.0")
        classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:$kotlinVersion")
    }
}

allprojects {
    repositories {
        // First, and only while the Android SDK is unreleased: `./gradlew :otp:publishToMavenLocal`
        // in the android directory of the source repository is what puts it there. Once the
        // artifact is on Maven Central this line does nothing but miss.
        mavenLocal()
        google()
        mavenCentral()
    }
}

plugins {
    id("com.android.library")
}

android {
    namespace = "com.otp.sdk.flutter"

    // 37, not the Flutter template's default 36: com.otp:sdk-android:0.2.0 pulls in AndroidX
    // libraries that require compiling against 37.
    compileSdk = 37

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    sourceSets {
        getByName("main") {
            java.srcDirs("src/main/kotlin")
        }
        getByName("test") {
            java.srcDirs("src/test/kotlin")
        }
    }

    defaultConfig {
        // 26, not the Flutter template's own 24. Hardware-backed key attestation is the security
        // floor of the SDK underneath and it is only guaranteed from here, so an app that builds
        // against plain Flutter can fail to build against this package. That is the reason, not an
        // oversight: see the repository README.
        minSdk = 26
    }

    testOptions {
        unitTests {
            isIncludeAndroidResources = true
            all {
                it.useJUnitPlatform()

                it.outputs.upToDateWhen { false }

                it.testLogging {
                    events("passed", "skipped", "failed", "standardOut", "standardError")
                    showStandardStreams = true
                }
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    implementation("com.otp:sdk-android:0.2.0")

    testImplementation("org.jetbrains.kotlin:kotlin-test")
    testImplementation("org.mockito:mockito-core:5.0.0")
}
