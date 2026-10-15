# Troubleshooting

**"The native torrent engine is not available on this platform."**
The app is running outside Android, or the debug APK was built without the
`arm64-v8a` ABI. Build with
`flutter build apk --debug --target-platform android-arm64` and run on an arm64
device.

**A transfer never leaves "resolving metadata".**
Metadata comes from peers/DHT and times out after 90 s. A magnet with no
reachable peers cannot resolve. Try adding the tracker list from the source page,
and confirm you are not on a network that blocks BitTorrent.

**Downloads do not continue in the background.**
Android may still stop a foreground service under aggressive battery
optimisation. Open Settings → Background to read exactly what the app does and
does not guarantee, and exempt the app if your OEM requires it.

**"CBR/RAR comics are not supported."**
Correct — there is no maintained permissive pure-Dart RAR decoder in this build.
Convert the archive to CBZ.

**A GitHub check reports a rate limit.**
Unauthenticated GitHub API calls are limited. Wait, or store a token (used only
for read-only requests).

**A manifest is reported as "unknown publisher" / "unsigned".**
`kPinnedPublisherKeys` is empty by default, so nothing verifies. That is the
fail-closed default. Add your publisher's Ed25519 public key to trust it.

**Cloud sync says "not authorised".**
The provider rejected the request. For Supabase this is usually a missing anon
key (Settings → Cloud) or Row Level Security blocking the row. Check that the
signed-in user owns the data.

**Playback fails immediately.**
Open the player's media-source panel. `PlaybackDiagnostics` distinguishes
network failure, an HTTP error page, an unsupported container/codec, a malformed
HLS/DASH manifest, and DRM that is not authorised. If it is the last one, the
content provider must authorise the device — the app will not circumvent it.

**Gradle is killed while building.**
`android/gradle.properties` is intentionally tuned small for constrained CI. On a
normal workstation you can raise `org.gradle.jvmargs` and `org.gradle.workers.max`.
