# Contributing

## Ground rules

1. **Android-first.** Android is the shipping target. Do not add desktop
   codepaths to satisfy a feature; keep platform-specific work behind an
   interface so ports stay possible.
2. **Real implementations only.** No fake progress, no fabricated peer counts,
   no placeholder playback, no "simulated" sync. If something is not
   implemented, mark it and say so in the UI and in `docs/status.md`.
3. **Local-first.** Downloads, reading and browsing must never require an
   account or a publisher backend.
4. **Fail closed.** Unknown publishers, unknown manifests and unknown
   capabilities are rejected rather than ignored.

## Before you push

```bash
flutter analyze          # must be clean (0 issues)
flutter test             # must be green
flutter build apk --debug --target-platform android-arm64
```

## Adding a dependency

- Check that it is maintained and that you know its licence.
- Prefer a package that the project already uses.
- Never bake a secret into the app; put it in `flutter_secure_storage` or ask
  the user for it.

## Changing the database

Append a **new** entry to `AppMigrations.all`. Never edit a shipped migration —
the same statements run for fresh installs and upgrades, which is what makes
upgrades safe.

## Adding a manifest field or capability

Update `ManifestValidator`, `docs/source-manifest.md`, and the tests together. A
manifest must never be able to request a new permission or execute code.
