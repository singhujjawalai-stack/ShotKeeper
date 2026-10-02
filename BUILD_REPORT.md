# ShotKeeper APK Build Report

## Status: FIXED — APK built
- Root cause: conflicting stale `android/settings.gradle` (Groovy, missing `includeBuild`) overrode `settings.gradle.kts`; stale `android/build.gradle` (AGP 8.1.0) conflicted with `.kts` (AGP 9.1.0).
- Fix: renamed `android/settings.gradle` → `.bak` and `android/build.gradle` → `.bak` (preserved); kept `.kts` versions.
- Build command after fix: `flutter clean; flutter pub get; flutter build apk --release --split-per-abi --target-platform android-arm64`
- Result: `√ Built build/app/outputs/flutter-apk/app-arm64-v8a-release.apk (17.8MB)`
- Flutter version after upgrade: 3.47.5 • channel stable
- Note: build produces the `java.lang.System` native-access warning and KGP compatibility notice (same as Not Today); APK installs directly (Play Protect avoided).

## Features Delivered (code + built APK)
1. Popup on screenshot detection: 1h/4h/12h/1d/3d/1w preset buttons + Custom (number + hour/min/day dropdown) + Delete Now
2. Remember for future: CheckBox saves preference; future screenshots skip popup automatically
3. Auto-detection: MediaStore `ContentObserver` + 60s poll fallback (`ScreenshotDetectorService`)
4. Scheduled deletion: `DeletionJobService` deletes file after selected duration
5. Direct install: Play Protect avoided; APK size 17.8MB (arm64 split)
