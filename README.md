# GLITCH//RUN

An offline-first top-down 3D action roguelite built with Godot 4.7.2, GDScript, and KayKit 3D Dungeon assets.

## Gameplay & Presentation

- **Top-Down 3D Dungeon:** High-angle 3D perspective with directional lighting, dynamic shadows, and modular KayKit stone dungeon tiles, walls, pillars, crates, and barrels.
- **Sectors 1 to 5:** Clear escalating combat chambers with tactical cover barriers and enemy rosters.
- **Sector Clear & Upgrade Draft:** Defeating all hostiles opens a 3-card upgrade draft to reconfigure weapon output, mobility, or chassis durability (game pauses cleanly during selection).
- **Sector 6 (Boss Chamber):** Face the **NEXUS // OVERLORD**, featuring telegraphed radial projectile bursts and heavy kinetic surges.
- **Victory & Defeat Screens:** Complete stats breakdown (time, eliminations, upgrades chosen) with instant restart.

## Hostile Roster

- **Chaser:** Relentless melee construct that pursues and deals contact damage.
- **Shooter:** Kiting ranged construct that projects a telegraphed laser sight before firing energy bolts.
- **Dasher:** High-speed blade construct that locks trajectory with a flashing telegraph, lunges forward, and stalls on recovery.
- **Nexus Overlord (Boss):** Massive core guarded by rotating orbital shield nodes, unleashing 8-way radial bursts and heavy charge slams.

## Controls

- Move with **WASD** or arrow keys (along the X/Z dungeon floor).
- Aim with the mouse (calculated via 3D raycast to floor plane) and hold **Left Mouse Button** (or **J**) to fire.
- Dash with **Shift** or **Space** (includes invulnerability frames to dodge through incoming fire).
- On mobile/touchscreens, use the left virtual joystick to move, hold and drag the right thumb stick to aim & fire in 360°, and tap **DASH**.

## Open & Run

Open this folder in **Godot 4.7.2 stable** and run `res://scenes/main.tscn` (or press F5 / F6). All 3D scenes, KayKit models, and autoload singletons (`RunState`) are configured.
