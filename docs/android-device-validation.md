# Android physical-device validation

Run this matrix on at least Android 10, 13, and 14+ devices, including one OEM
with aggressive battery management (Samsung, Xiaomi, Oppo, or Vivo). Record the
device model, Android build, result, and screenshots/logcat evidence.

## Permissions and Storage Access Framework

- Fresh install: deny, grant, and “selected photos only” for every media prompt.
- Verify all-files access returns correctly after leaving and re-entering Settings.
- Browse SD card, Downloads, cloud/document providers, and read-only providers.
- Confirm cancelled pickers, revoked access, moved files, and stale document URIs
  fail with a useful message and never mutate another file.

## Notifications and background execution

- Enable Storage alerts on Android 13+: grant and deny the system prompt; denial
  must leave the toggle off. Revoke permission later in system settings.
- Trigger each worker with Android Studio WorkManager Inspector (or the exact job
  ID reported by `adb shell dumpsys jobscheduler`) and verify notifications appear.
- Enable battery saver, Doze, restricted background usage, reboot, and force-stop.
  Verify Android may defer work, and that periodic work resumes after reboot but
  does not run after a force-stop until the app is opened again.
- Confirm cleanup-rule workers never scan or delete shared-storage files.

## Recovery, conflicts, sharing, and OEM behavior

- Restore when the original path is free, already contains a file, is read-only,
  is on removed media, and has insufficient free space. Existing files must not
  be overwritten silently.
- Expire a recovery item, run the purge worker, and confirm only the app-owned
  recovery copy and matching metadata are removed. Disable auto-purge and repeat.
- Share each supported MIME type to several targets, cancel the chooser, revoke
  target access, and confirm URI permission is temporary and read-only.
- Repeat scheduled-work checks with each OEM’s auto-start/background restriction
  enabled and disabled; document the relevant settings path for support guidance.

Use `adb shell dumpsys package ai.spacepilot.app`, `adb shell dumpsys jobscheduler`,
Android Studio WorkManager Inspector, and filtered logcat output as evidence.
