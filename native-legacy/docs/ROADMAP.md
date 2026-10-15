# Status against the completion criteria

Honest accounting. Nothing below is marked done on the strength of a green build
alone.

| # | Criterion | Status |
|---|---|---|
| 1 | Builds and installs on a real Android device | **Builds** — debug APK produced, debug-signed, arm64-v8a `libtorrent4j.so` packaged. **Install on a device has not been performed:** this environment has no device or emulator. |
| 2 | Downloads an actual controlled test torrent | **Blocked** — needs a device. The engine path (`fetchMagnet` → `TorrentInfo` → `download` → `find`) is implemented and compiles; it has never executed. |
| 3 | Pause/resume correctness | **Blocked** — `pause()`/`resume()`/resume-data saving are implemented; behaviour unverified without a device. |
| 4 | Background behaviour tested on Android | **Blocked** — foreground service and WorkManager wiring are implemented; Doze/OEM battery behaviour is untestable here. |
| 5 | EPUBs and comics open | **Partially verified** — format detection, EPUB container/OPF parsing, archive page ordering and text pagination are unit-tested (9 reader tests). Actual rendering on a phone is unverified. |
| 6 | Subscriptions detect a published version change | **Partially verified** — version comparison, manifest discovery and update evaluation are unit-tested with real fixtures. Live GitHub calls unverified (no network run in tests). |
| 7 | Invalid signatures and corrupted downloads rejected | **Verified at the unit level** — Ed25519 round-trip, unpinned-key rejection, tampered-message rejection, SHA-256 vectors, zip-slip and traversal rejection are all asserted by tests. End-to-end rejection of a corrupted payload is not exercised on device. |
| 8 | Storage and permission failures handled | **Implemented, unverified** — SAF pickers, denied-permission and storage-full states exist in the UI; exercised only by compilation. |
| 9 | Usable on a typical phone, touch-first | **Implemented, unverified** — bottom navigation, sheets, pagers and gesture-friendly reader; needs a human on a device. |

## Next steps, in order

1. **Phase 1 (the real blocker):** install `app-debug.apk` on an arm64 device and
   validate the engine — magnet metadata retrieval, DHT bootstrap, tracker
   discovery, peers, pause/resume, and sustained transfer under Doze.
2. Wire the foreground service start/stop to real transfer state on device and
   verify the notification is accurate.
3. Add emulator ABI artifacts (`libtorrent4j-android-x86_64`) for CI smoke tests.
4. Adopt Readium's navigator for EPUB presentation and resolve in-archive
   resources so chapters render with their own images and styles.
5. Publisher key management: populate `TrustedPublisherKeys.PINNED` from a real
   release-signing key, and move the private key into the Android Keystore-backed
   release process.
6. Release signing (`keystore.properties`, untracked) and Play/distribution
   requirements, including the UnRAR-licence review for CBR support.
