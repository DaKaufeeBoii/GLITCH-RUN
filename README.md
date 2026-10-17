# GLITCH//RUN

An offline-first top-down action roguelite prototype built with Godot 4.7.2 and GDScript.

## First playable slice

- Move with **WASD** or the arrow keys.
- Aim with the mouse and hold the left mouse button (or **J**) to fire.
- Dash with **Shift** or **Space**.
- On a touchscreen, drag the left virtual stick to move, hold the right side to aim and fire, and tap **DASH**.
- Defeat the chasing enemy, avoid contact damage, and see how long you can survive. The run ends at zero health; use **RESTART RUN** to begin again.

This build uses placeholder vector shapes so combat and controls can be tuned before pixel art. It has no network, ads, or machine-learning dependency.

## Open the project

Open this folder in **Godot 4.7.2 stable** and run `scenes/main.tscn` (or press F6 after opening the main scene). The project entry point is already set to `res://scenes/main.tscn`.

For Android export, install the matching Godot export templates and configure the Android SDK and Java SDK paths in Editor Settings. Export and try the first build on a physical phone before tuning the touch controls further.
