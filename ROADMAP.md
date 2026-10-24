# Remaining release work

1. Verify current APKs between physical Android 6/J7 and modern phones; QR/audio
   tests must keep radios off and compare actual output hashes.
2. Finish brand icon/adaptive/monochrome/splash assets and bilingual accessible UX.
3. Add accurate audio duration estimates, bounded pairing timeouts, lifecycle
   cancellation tests and robust cleanup across async callbacks/navigation.
4. Commit Android scaffold and lock both dependency profiles; finish license audit.
5. Improve LAN/Bluetooth discovery and connection recovery, file-picker/share
   integration, save destinations and history consistency.
6. Add opt-in Smart Share based on actual availability; never switch channels silently.
7. Independent protocol/security review; protect production signing and validate
   Play requirements before any store publication (requires fresh authorization).

Persistent cross-restart resume, Wi-Fi Direct and colored optical transport are
not supported and are not advertised as implemented.
