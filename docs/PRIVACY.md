# GLITCH//RUN — Privacy and Data Handling Policy

**GLITCH//RUN** is engineered from the ground up as a fully **offline-first, single-player game**.

---

## 1. Zero Network Transmission

- `GLITCH//RUN` does **not** connect to any remote servers, cloud backends, analytics services, advertising networks, or third-party SDKs.
- The Android application manifest requests **zero network permissions** (`android.permission.INTERNET` is explicitly disabled in `export_presets.cfg`).
- The game functions 100% offline without requiring internet or Wi-Fi connectivity at any time.

---

## 2. Local Storage & Data Retention

All data generated during gameplay is stored strictly within the application's sandboxed local internal storage directory (`user://`):

| File Path | Purpose | Sensitive Data |
| :--- | :--- | :--- |
| `user://save_data.json` | Persistent high score, depth, sector, time, and difficulty | None |
| `user://settings.json` | Master/music/SFX volume, screen shake toggle, and haptics preference | None |
| `user://logs/glitch_run_qa.log` | Local diagnostics log (engine version, memory usage, warnings) capped at 256KB | None (Zero PII) |

---

## 3. Crash and Diagnostics Logging

- Diagnostics are logged strictly to `user://logs/glitch_run_qa.log` on device storage for local QA and player debugging.
- No hardware IDs, IP addresses, advertising IDs, or user identities are ever collected or stored.
- The diagnostics log automatically rotates and is capped at 256 KB to ensure minimal disk space utilization.

---

## 4. User Rights & Data Deletion

Because all game data resides strictly on the local device, uninstalling the application or using Android's "Clear Storage" option in App Info completely and irrevocably purges all saves, preferences, and logs.
