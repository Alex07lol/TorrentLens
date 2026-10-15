plugins {
    alias(libs.plugins.android.library)
    alias(libs.plugins.kotlin.serialization)
}

android {
    namespace = "dev.torrentlens.core.torrent"
    compileSdk = 37
    defaultConfig {
        minSdk = 28
        // arm64-v8a is the shipping ABI. Emulator ABIs are added with the
        // matching org.libtorrent4j:libtorrent4j-android-* artifact when needed.
        ndk { abiFilters += "arm64-v8a" }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

dependencies {
    api(project(":core:domain"))
    implementation(project(":core:data"))
    implementation(libs.kotlinx.coroutines.android)
    implementation(libs.kotlinx.coroutines.core)
    implementation(libs.libtorrent4j)
    implementation(libs.libtorrent4j.android.arm64)
}
