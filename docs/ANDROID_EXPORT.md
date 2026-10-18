# GLITCH//RUN — Android Build, Hardening & Export Guide

This document details the configuration, SDK prerequisites, and export workflows for **GLITCH//RUN** on Android.

---

## 1. Build Identification & Specifications

- **Package ID:** `com.antigravity.glitchrun`
- **Application Name:** `GLITCH//RUN`
- **Target Platform:** Android (Sensor Landscape)
- **Minimum SDK:** API Level 24 (Android 7.0 Nougat) — covers >97% of active Android devices
- **Target SDK:** API Level 34 (Android 14)
- **Architectures:** `arm64-v8a` (Primary), `armeabi-v7a` (32-bit fallback)
- **Engine Version:** Godot 4.7.2-stable (GL Compatibility renderer)
- **Export Formats:**
  - Debug / Sideloading: `.apk`
  - Production Release: `.aab` (Android App Bundle) or signed `.apk`

---

## 2. Android Permissions & Privacy Architecture

`GLITCH//RUN` is architected as an **offline-first, single-player action roguelite**.

### Configured Permissions
- `android.permission.VIBRATE`: Enables subtle haptic feedback on phase dash and taking damage (can be disabled in in-game Settings).

### Prohibited / Omitted Permissions
- `android.permission.INTERNET`: **DISABLED**. The game has zero network connectivity, transmits zero analytics, and makes no network requests.
- `android.permission.ACCESS_NETWORK_STATE`: **DISABLED**.
- `android.permission.READ_EXTERNAL_STORAGE` / `WRITE_EXTERNAL_STORAGE`: **DISABLED**. Saves and diagnostics use app-scoped internal storage (`user://`).

---

## 3. Prerequisites & Environment Setup

To export on Android from Godot:
1. **Java Development Kit:** OpenJDK 17 or Eclipse Temurin 17.
2. **Android SDK:**
   - Platform Tools (v34+)
   - Build Tools (v34.0.0)
   - Android SDK Platform 34
3. **Godot Editor Settings Configuration:**
   - `export/android/java_sdk_path` -> Path to JDK 17 (e.g. `C:/Program Files/Eclipse Adoptium/jdk-17...`)
   - `export/android/android_sdk_path` -> Path to Android SDK (e.g. `C:/Users/<User>/AppData/Local/Android/Sdk`)
   - `export/android/debug_keystore` -> Path to `debug.keystore` (generated automatically or via keytool).

---

## 4. Debug Export Workflow (No Release Secrets Needed)

To build a debug APK for local testing on a connected device:

### Via Command Line:
```bash
# Ensure target build directory exists
mkdir -p build/android

# Export debug APK using the defined Android preset in export_presets.cfg
godot --headless --export-debug "Android" build/android/glitch_run_debug.apk
```

### Install to Device via ADB:
```bash
adb install -r build/android/glitch_run_debug.apk
adb shell am start -n com.antigravity.glitchrun/com.godot.game.GodotApp
```

---

## 5. Release Export Workflow (Signing Secrets Separation)

> [!CAUTION]
> **Never commit keystore files (`.keystore`, `.jks`) or release passwords to source control.**
> All release signing credentials must be managed via local environment variables or external CI/CD secret vaults.

### Generating a Release Keystore:
```bash
keytool -v -genkeypair -v -keystore glitch_run_release.keystore -alias glitch_run -keyalg RSA -keysize 2048 -validity 10000
```

### Environment Variables for Release Build:
Set the following environment variables in your local terminal or CI pipeline:
```bash
export GODOT_ANDROID_KEYSTORE_PATH="/path/to/glitch_run_release.keystore"
export GODOT_ANDROID_KEYSTORE_USER="glitch_run"
export GODOT_ANDROID_KEYSTORE_PASS="<your_secure_password>"
```

### Exporting Signed Release AAB / APK:
In Godot 4:
```bash
godot --headless --export-release "Android" build/android/glitch_run_release.aab
```

---

## 6. Physical Device Testing Matrix

When validating release candidates on physical hardware, test against:
1. **Low/Mid-Range Device:** e.g. Snapdragon 600-series / Helio G-series, 3GB–4GB RAM, Android 10–12.
2. **Modern Aspect Ratio Device:** 19.5:9 or 20:9 with camera notch/hole punch to verify HUD margin boundaries.
3. **Session Verification Steps:**
   - **Cold Install & Launch:** Starts directly into title menu in sensor landscape without orientation flip.
   - **Audio Focus & Backgrounding:** Switch apps during combat -> game pauses automatically -> audio cuts cleanly -> resume returns on explicit tap.
   - **Back Button Navigation:** Modal dismiss -> Pause menu -> Main menu confirmation.
   - **Save Migration & Corruption Recovery:** Malformed or truncated save files in `user://` gracefully reset to defaults with 0 crash reports.
   - **Thermal & Frame Rate:** 60 FPS sustained with bounded active particles and zero memory leaks over a 20-minute multi-sector run.
