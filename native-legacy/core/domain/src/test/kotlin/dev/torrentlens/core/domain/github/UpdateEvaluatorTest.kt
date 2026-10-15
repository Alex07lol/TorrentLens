package dev.torrentlens.core.domain.github

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class UpdateEvaluatorTest {

    private fun manifest(
        version: String,
        schema: Int = 1,
        artifacts: List<ManifestArtifact> = emptyList(),
    ) = UpdateManifest(schemaVersion = schema, version = version, artifacts = artifacts)

    @Test
    fun `reports an available update`() {
        val d = UpdateEvaluator.evaluate("1.0.0", manifest("1.1.0"))
        assertTrue(d is UpdateDecision.UpdateAvailable)
        assertEquals("1.1.0", (d as UpdateDecision.UpdateAvailable).latestVersion)
    }

    @Test
    fun `reports up to date and newer installations`() {
        assertTrue(UpdateEvaluator.evaluate("1.1.0", manifest("1.1.0")) is UpdateDecision.UpToDate)
        assertTrue(UpdateEvaluator.evaluate("2.0.0", manifest("1.1.0")) is UpdateDecision.InstalledIsNewer)
    }

    @Test
    fun `an unknown installed version is treated as needing the update`() {
        assertTrue(UpdateEvaluator.evaluate("dev-build", manifest("1.1.0")) is UpdateDecision.UpdateAvailable)
    }

    @Test
    fun `rejects manifests it cannot trust or understand`() {
        assertEquals(
            UpdateDecision.Rejected(ManifestRejection.UNSUPPORTED_SCHEMA),
            UpdateEvaluator.evaluate("1.0.0", manifest("9.9.9", schema = 99)),
        )
        assertEquals(
            UpdateDecision.Rejected(ManifestRejection.UNPARSEABLE_VERSION),
            UpdateEvaluator.evaluate("1.0.0", manifest("not-a-version")),
        )
    }

    @Test
    fun `artifact selection prefers android arm64 then any android then platform-agnostic`() {
        val artifacts = listOf(
            ManifestArtifact(name = "desktop.zip", url = "u", platform = "windows"),
            ManifestArtifact(name = "phone.apk", url = "u", platform = "android", abi = "x86_64"),
            ManifestArtifact(name = "phone-arm64.apk", url = "u", platform = "android", abi = "arm64-v8a"),
        )
        val d = UpdateEvaluator.evaluate("1.0.0", manifest("2.0.0", artifacts = artifacts))
        assertEquals("phone-arm64.apk", (d as UpdateDecision.UpdateAvailable).applicableArtifact!!.name)

        val androidOnly = listOf(
            ManifestArtifact(name = "phone-x86.apk", url = "u", platform = "android", abi = "x86"),
            ManifestArtifact(name = "any.zip", url = "u"),
        )
        val d2 = UpdateEvaluator.evaluate("1.0.0", manifest("2.0.0", artifacts = androidOnly))
        assertEquals("phone-x86.apk", (d2 as UpdateDecision.UpdateAvailable).applicableArtifact!!.name)
    }
}
