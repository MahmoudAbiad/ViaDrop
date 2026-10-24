# Recovery development branch

This branch was copied from the source-preservation checkpoint on main. It must not modify main, and can be merged only after review.

## First recovery milestone

- Add a runnable Flutter entry point, Arabic RTL and approved ViaDrop palette.
- Show transport channels honestly as unverified, rather than simulating success.
- Exercise existing AES-GCM envelope in a local file-selection flow.
- Restore regression tests for encryption roundtrip and transfer state.
- Use GitHub Actions to regenerate the deleted Android Flutter skeleton and compile a debug APK.

## Known limits

This is not a completed file-sharing app. Physical two-phone transfers, channel UIs, Android runtime permission behavior, actual microphone/camera tests, restored icon files, and security review are still pending. A green APK build demonstrates compilability, not channel functionality. Upstream license notices remain applicable.

The base Android files generated in CI should be committed explicitly once the build passes, to avoid depending on generation forever.
