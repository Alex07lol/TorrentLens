plugins {
    alias(libs.plugins.kotlin.jvm)
    alias(libs.plugins.kotlin.serialization)
}

kotlin {
    jvmToolchain(17)
    // The domain layer is deliberately platform-free: it must compile and test
    // on a plain JVM so the rules are verifiable without a device.
}

dependencies {
    api(libs.kotlinx.serialization.json)
    testImplementation(libs.junit)
}

tasks.withType<Test> { useJUnit() }
