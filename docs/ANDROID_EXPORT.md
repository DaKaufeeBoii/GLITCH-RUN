# GLITCH//RUN — Android Build and Export

This guide describes the Android settings currently stored in `export_presets.cfg`. Verify export succeeds with the installed Godot version and SDK before distributing a build.

## Project preset

- Godot: 4.7.2 stable
- Preset name: `Android`
- Package ID: `com.antigravity.glitchrun`
- Orientation: landscape
- Minimum SDK: 24
- Target SDK: 36
- Architecture: ARM64 (`arm64-v8a`)
- Version code: 2
- Version name: `0.3`
- Export format: APK (the preset currently has `gradle_build/export_format=0`)
- Permissions enabled in the preset: `VIBRATE`; networking and external storage permissions are disabled.

Treat `export_presets.cfg` as authoritative if any value in this guide drifts.

## Requirements

Install a JDK and Android SDK supported by Godot 4.7.2, including the Android platform and build tools needed for the configured target SDK. Install the matching Godot Android export templates. In Godot Editor Settings, configure:

1. `Export > Android > Java SDK Path`
2. `Export > Android > Android SDK Path`

If Godot reports that it cannot open the Android `build-tools` directory, confirm the SDK path points to the SDK root and that the required platform/build-tools packages are installed. The project’s Android preset does not include the SDK or export templates.

## Debug APK

From the project root, with Godot on `PATH`:

```powershell
New-Item -ItemType Directory -Force build/android | Out-Null
godot --headless --path . --export-debug "Android" build/android/glitch_run_debug.apk
```

On Windows, use the full path to `Godot_v4.7.2-stable_win64_console.exe` if the `godot` command is unavailable. Install on a connected device with Android Platform Tools:

```powershell
adb install -r build/android/glitch_run_debug.apk
```

## Release builds

Before publishing, configure a release keystore in the Android export preset through Godot. Keep the keystore and passwords outside source control; do not use debug signing for a public release. Increase `package/version_code` for each uploaded build and update `package/version_name` intentionally. Select the format required by your distribution channel; the current preset is configured for APK export, so verify and change the export format if an Android App Bundle is required.

Review current distribution requirements in the relevant store console before release. This document does not claim that the current project is store-ready or that a release build has been signed or device-tested.

## Device verification checklist

- [ ] Install and cold-launch on an ARM64 Android device in landscape.
- [ ] Check touch controls, HUD margins, and menus on the target screen sizes/aspect ratios.
- [ ] Check pause, Android Back navigation, background/resume, audio, and haptics.
- [ ] Play through the first sector and verify enemies begin at baseline without collecting learning evidence. Afterward, verify that first evolution remains locked until the first biome is complete and later promotions are spaced by 3, 5, then 7 floors.
- [ ] Verify the 50 HP starting boss phases, +5 HP per sector scaling, the three family bosses from biome 2 onward, and their movement/attack telegraphs on a phone-sized display.
- [ ] Verify BREACHER and LONGSHOT unlock costs display as 1,000 and 3,000 Bits.
- [ ] Verify a run reset/death clears run-scoped enemy learning.
- [ ] Verify local settings and save data survive app restart and recover from malformed files.
- [ ] Check frame pacing, heat, and memory over a longer run on representative devices.
- [ ] Confirm the final release artifact installs and launches using its production signing configuration.
