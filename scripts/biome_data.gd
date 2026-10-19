extends RefCounted
class_name BiomeData
## Biome Definition & Visual Aesthetic System for GLITCH//RUN.
## Manages distinct biomes with customized color palettes, wall rails, grid lines, and atmosphere.

const BIOMES: Array[Dictionary] = [
	{
		"id": "NEON_PROTOCOL",
		"name": "NEON PROTOCOL",
		"subtitle": "High-frequency cybergrid calibration sector",
		"floor_color": Color(0.03, 0.05, 0.09, 1.0),       # #080c16
		"grid_color": Color(0.0, 0.94, 1.0, 0.22),         # #00f0ff
		"wall_glow": Color(0.0, 0.94, 1.0, 1.0),           # Neon cyan
		"wall_inner": Color(0.04, 0.10, 0.18, 0.95),       # Dark tech slate
		"accent": Color(0.22, 0.74, 0.97, 1.0),            # #38bdf8
		"hazard": Color(0.94, 0.27, 0.27, 1.0),            # #ef4444
		"laser_gate": Color(0.0, 0.94, 1.0, 0.85),
		"laser_locked": Color(0.95, 0.20, 0.20, 0.95),
		"portal_color": Color(0.15, 0.85, 1.0, 1.0),
		"sector_tint": Color(0.88, 0.95, 1.0)
	},
	{
		"id": "CRYO_SUBSYSTEM",
		"name": "CRYO SUBSYSTEM",
		"subtitle": "Sub-zero crystalline conduits & frozen memory banks",
		"floor_color": Color(0.04, 0.08, 0.15, 1.0),       # Glacial slate
		"grid_color": Color(0.49, 0.83, 0.99, 0.25),       # #7dd3fc
		"wall_glow": Color(0.22, 0.74, 0.97, 1.0),         # Frost blue
		"wall_inner": Color(0.06, 0.14, 0.25, 0.95),       # Chilled conduit
		"accent": Color(0.88, 0.95, 1.0, 1.0),             # Ice white
		"hazard": Color(0.96, 0.25, 0.37, 1.0),            # Frozen crimson
		"laser_gate": Color(0.49, 0.83, 0.99, 0.85),
		"laser_locked": Color(1.0, 0.20, 0.40, 0.95),
		"portal_color": Color(0.40, 0.90, 1.0, 1.0),
		"sector_tint": Color(0.80, 0.92, 1.0)
	},
	{
		"id": "TOXIC_BIOSYSTEM",
		"name": "TOXIC BIOSYSTEM",
		"subtitle": "Algorithmic flora & synthetic bio-matrix corruption",
		"floor_color": Color(0.03, 0.10, 0.06, 1.0),       # Deep moss
		"grid_color": Color(0.20, 0.73, 0.50, 0.24),       # #34d399
		"wall_glow": Color(0.06, 0.78, 0.38, 1.0),         # Emerald green
		"wall_inner": Color(0.05, 0.16, 0.10, 0.95),       # Bio-casing
		"accent": Color(0.43, 0.91, 0.72, 1.0),            # Bio-luminescent mint
		"hazard": Color(0.98, 0.75, 0.14, 1.0),            # Toxic amber
		"laser_gate": Color(0.20, 0.85, 0.50, 0.85),
		"laser_locked": Color(1.0, 0.35, 0.10, 0.95),
		"portal_color": Color(0.25, 0.95, 0.65, 1.0),
		"sector_tint": Color(0.85, 1.0, 0.90)
	},
	{
		"id": "CRIMSON_CORE",
		"name": "CRIMSON CORE",
		"subtitle": "Overclocked magma hypergrid & molten thermal void",
		"floor_color": Color(0.10, 0.04, 0.04, 1.0),       # Charcoal amber
		"grid_color": Color(0.97, 0.44, 0.44, 0.25),       # #f87171
		"wall_glow": Color(0.94, 0.25, 0.25, 1.0),         # Molten crimson
		"wall_inner": Color(0.20, 0.06, 0.06, 0.95),       # Thermal shielding
		"accent": Color(0.99, 0.80, 0.83, 1.0),            # Incandescent core
		"hazard": Color(0.98, 0.57, 0.24, 1.0),            # Magma burst
		"laser_gate": Color(0.95, 0.40, 0.20, 0.85),
		"laser_locked": Color(1.0, 0.10, 0.10, 0.95),
		"portal_color": Color(1.0, 0.40, 0.30, 1.0),
		"sector_tint": Color(1.0, 0.85, 0.80)
	}
]


static func get_biome(biome_index: int) -> Dictionary:
	var idx := posmod(biome_index - 1, BIOMES.size())
	return BIOMES[idx]


static func get_biome_count() -> int:
	return BIOMES.size()
