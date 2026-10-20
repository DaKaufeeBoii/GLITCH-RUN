# GLITCH//RUN

GLITCH//RUN is an offline, single-player, top-down action roguelite built with Godot 4.7.2 and GDScript. The current game targets Android phones in landscape orientation and uses touch controls.

## Current game

- Procedurally generated floors connect combat rooms and optional recovery, shop, gift, and other special rooms. Floor routes vary; special rooms are not guaranteed on every floor.
- Combat rooms use multiple waves and varied enemy compositions. Sector progression and room generation are seeded for reproducible layouts.
- The first sector is an onboarding sector: enemies begin at baseline forms and do not collect learning evidence. After it is cleared, eligible enemies start learning from their own encounters, but the first evolution cannot happen until biome 1 is complete. Later evolution milestones are separated by 3, 5, then 7 completed floors. Evolution and evidence reset when a run ends or restarts.
- Bosses begin at 50 HP per phase and gain 5 HP per completed sector. Biome-final bosses have two phases; sector mid-bosses have one. Three enemy-family bosses join the rotation from biome 2, with bounded arenas, obstacle-aware movement, and readable attack telegraphs.
- Archived Bits unlock permanent characters: BREACHER costs 1,000 Bits and LONGSHOT costs 3,000 Bits.
- Runs include touch-first menus, pause and quit flows, local settings, synthesized music and effects, and local save data.
- The game runs offline. Settings, saves, and diagnostic logs stay in app-local `user://` storage.

## Android controls

| Action | Touch control |
| --- | --- |
| Move | Left virtual joystick |
| Aim and fire | Right virtual joystick |
| Dash | On-screen Dash button |
| Reload | On-screen Reload button |
| Pause | Top-right pause button |
| Debug overlay | HUD debug button (development builds) |
| Back navigation | Android system Back button |

## Project setup

- Engine: Godot 4.7.2 stable
- Renderer: GL Compatibility
- Orientation: landscape
- Android package: `com.antigravity.glitchrun`
- Android minimum SDK: 24
- Android target SDK: 36
- Android architecture: ARM64 (`arm64-v8a`)
- Android export preset: `Android` in `export_presets.cfg`

Configure the JDK and Android SDK paths in Godot Editor Settings, and install matching Android export templates before exporting. See [docs/ANDROID_EXPORT.md](docs/ANDROID_EXPORT.md).

### Export a debug APK

From the project root, with Godot available on `PATH`:

```powershell
New-Item -ItemType Directory -Force build/android | Out-Null
godot --headless --path . --export-debug "Android" build/android/glitch_run_debug.apk
```

On Windows, replace `godot` with the path to `Godot_v4.7.2-stable_win64_console.exe` if it is not on `PATH`.

## Run the deterministic scenarios

The test runner is `scripts/test_runner.gd`. From the project root:

```powershell
godot --headless --path . --script res://scripts/test_runner.gd
```

The current suite contains 59 scenarios covering procedural generation and reachability, progression, enemy AI and evolution, bosses, persistence, menus, and Android input/export configuration. A headless run needs a writable Godot `user://` location for save/settings persistence scenarios. See the current test output before treating this count as verified for a later build.

## Useful project paths

- `project.godot` — main scene, autoloads, display, and renderer settings.
- `scenes/ui/start_screen.tscn` — initial splash screen.
- `scenes/main.tscn` — gameplay scene.
- `scripts/game.gd` — gameplay and room orchestration.
- `scripts/dungeon_generator.gd` — floor and room graph generation.
- `scripts/run_progression.gd` — sectors, floors, waves, and difficulty progression.
- `scripts/encounter_director.gd`, `scripts/evolution_manager.gd` — encounter tactics and run-scoped enemy learning/evolution.
- `scripts/test_runner.gd`, `scripts/test_director.gd` — deterministic scenarios.
- `docs/ANDROID_EXPORT.md` — Android build/export guide.
- `docs/PRIVACY.md` — local data and network behavior.
- `docs/STORE_LISTING.md` — draft store copy and asset planning; verify claims and store requirements before publishing.

## Documentation status

`plan.md` is a historical implementation snapshot. `ANTIGRAVITY_IMPLEMENTATION_PLAN.md` is a design proposal for more open-ended learned enemy behavior, not a guarantee that every proposed behavior is implemented. Use this README and the source code as the current project reference.
