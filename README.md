# GLITCH//RUN

An offline-first top-down action roguelite built with Godot 4.7.2 and GDScript.

## Gameplay Loop

- **Sectors 1 to 5:** Clear escalating combat sectors featuring varied obstacle configurations and enemy rosters.
- **Sector Clear & Upgrade Draft:** Defeating all hostiles opens a 3-card upgrade draft to reconfigure your weapon, mobility, or chassis.
- **Sector 6 (Boss Chamber):** Face the **NEXUS // OVERLORD**, featuring telegraphed radial projectile bursts and heavy kinetic surges.
- **Victory & Defeat Screens:** Complete stats breakdown (time, eliminations, upgrades chosen) with instant restart.

## Hostile Roster

- **Chaser (Red Diamond):** Relentless pursuit with contact damage.
- **Shooter (Amber Hexagon):** Maintains distance, traces a telegraphed warning laser, and fires energy bolts.
- **Dasher (Magenta Chevron):** Stalks at range, locks trajectory with a flashing telegraph, and lunges at high speed.
- **Nexus Overlord (Boss):** Massive core guarded by orbital nodes, deploying radial projectile barrages and charge slams.

## Controls

- Move with **WASD** or arrow keys.
- Aim with the mouse and hold **Left Mouse Button** (or **J**) to fire.
- Dash with **Shift** or **Space** (includes invulnerability frames to dodge through incoming fire).
- On mobile/touchscreens, use the left virtual joystick to move, hold and drag the right thumb stick to aim & fire in 360°, and tap **DASH**.

## Open & Run

Open this folder in **Godot 4.7.2 stable** and run `res://scenes/main.tscn` (or press F5 / F6). All autoload singletons (`RunState`) and scenes are configured.
