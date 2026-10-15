plugins {
    alias(libs.plugins.android.library)
}

android {
    namespace = "dev.torrentlens.core.reader"
    compileSdk = 37
    defaultConfig { minSdk = 28 }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

dependencies {
    api(project(":core:domain"))
    implementation(libs.kotlinx.coroutines.core)
    implementation(libs.androidx.core.ktx)
    // CBR support is isolated here because junrar is under the UnRAR licence,
    // which is not a standard permissive OSS licence (see ADR 0003).
    implementation(libs.junrar)
    testImplementation(libs.junit)
}
