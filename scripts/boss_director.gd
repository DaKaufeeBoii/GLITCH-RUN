extends RefCounted
class_name BossDirector
## Run-level boss orchestration service.
## Schedules eligible boss encounters without immediate repetition,
## tracks within-run boss encounter history, and assigns bounded authored mutations
## with visible trade-offs when bosses return in endless runs.

const BossDefinition := preload("res://scripts/boss_definition.gd")
const BOSS_DEFINITION_SCRIPT := BossDefinition

var definitions: Dictionary = {} # boss_id -> BossDefinition
var encounter_history: Array[Dictionary] = []
var encounter_counts: Dictionary = {} # boss_id -> int
var last_scheduled_boss_id: String = ""


func _init() -> void:
	_register_default_bosses()


func _register_default_bosses() -> void:
	# 1. Nexus Overlord
	var nexus = BOSS_DEFINITION_SCRIPT.new(
		"nexus_overlord",
		"NEXUS OVERLORD",
		"SINGULARITY CORE",
		"res://scenes/enemies/boss.tscn",
		1,
		35,
		55.0,
		Color("f43f5e"),
		[
			{
				"id": "BURST_OVERCLOCK",
				"name": "BURST OVERCLOCK",
				"desc": "+2 PROJ PER BURST // +0.35s RECOVERY",
				"tier": 1
			},
			{
				"id": "TITAN_DASH",
				"name": "TITAN DASH",
				"desc": "+20% DASH SPEED // TELEGRAPH EXTENDED",
				"tier": 2
			}
		]
	)
	definitions["nexus_overlord"] = nexus

	# 2. Vector Sentinel
	var sentinel = BOSS_DEFINITION_SCRIPT.new(
		"vector_sentinel",
		"VECTOR SENTINEL",
		"ORBITAL DEFENSE MATRIX",
		"res://scenes/enemies/boss_sentinel.tscn",
		1,
		30,
		65.0,
		Color("06b6d4"),
		[
			{
				"id": "ORBITAL_ACCELERATION",
				"name": "ORBITAL ACCEL",
				"desc": "+25% SWEEP SPEED // REDUCED DURATION",
				"tier": 1
			},
			{
				"id": "SHARD_SYNCHRONY",
				"name": "SHARD SYNCHRONY",
				"desc": "DRONE MATRIX ACTIVATED // -15% BOSS HP",
				"tier": 2
			}
		]
	)
	definitions["vector_sentinel"] = sentinel

	# 3. Null Architect
	var architect = BOSS_DEFINITION_SCRIPT.new(
		"null_architect",
		"NULL ARCHITECT",
		"GRID CONTAINMENT CONSTRUCT",
		"res://scenes/enemies/boss_architect.tscn",
		2, # Unlocks at sector 2+
		40,
		45.0,
		Color("a855f7"),
		[
			{
				"id": "GRID_OVERLOAD",
				"name": "GRID OVERLOAD",
				"desc": "+1.0s PARTITION DURATION // +0.5s RECOVERY",
				"tier": 1
			},
			{
				"id": "WARP_ECHO",
				"name": "WARP ECHO",
				"desc": "AFTERSHOCK WARP // -15% BOSS HP",
				"tier": 2
			}
		]
	)
	definitions["null_architect"] = architect


func get_boss_definition(boss_id: String) -> BossDefinition:
	return definitions.get(boss_id, null)


func get_eligible_bosses(sector: int) -> Array[BossDefinition]:
	var eligible: Array[BossDefinition] = []
	for b_id in definitions:
		var b_def: BossDefinition = definitions[b_id]
		if b_def.min_sector <= sector:
			eligible.append(b_def)
	return eligible


func select_boss_for_sector(sector: int, run_seed: int, last_boss_id: String = "") -> BossDefinition:
	## Deterministically selects an eligible boss using run seed and enforces repetition cooldown.
	var eligible := get_eligible_bosses(sector)
	if eligible.is_empty():
		return definitions.get("nexus_overlord", null)

	var candidates: Array[BossDefinition] = []
	for b in eligible:
		if eligible.size() > 1 and b.boss_id == last_boss_id:
			continue # Repetition cooldown: do not repeat immediately if other options exist
		candidates.append(b)

	if candidates.is_empty():
		candidates = eligible

	# Deterministic pseudo-random index
	var hash_val := int(abs(sin(float(run_seed + sector * 37)) * 100000.0))
	var idx := hash_val % candidates.size()
	var selected: BossDefinition = candidates[idx]
	last_scheduled_boss_id = selected.boss_id
	return selected


func get_mutations_for_encounter(boss_id: String) -> Array[Dictionary]:
	## Returns capped authored mutations for a returning boss encounter.
	## First encounter has 0 mutations (clean baseline).
	var prior_encounters: int = encounter_counts.get(boss_id, 0)
	if prior_encounters == 0:
		return []

	var b_def := get_boss_definition(boss_id)
	if b_def == null or b_def.allowed_mutations.is_empty():
		return []

	# Cycle through authored mutation tiers (capped to 1 active mutation per returning fight)
	var mut_idx := (prior_encounters - 1) % b_def.allowed_mutations.size()
	var chosen_mut: Dictionary = b_def.allowed_mutations[mut_idx]
	return [chosen_mut]


func record_encounter(
	boss_id: String,
	sector: int,
	depth: int,
	outcome: String,
	mutations_applied: Array[Dictionary]
) -> void:
	## Persists boss encounter record into active run history.
	var record := {
		"boss_id": boss_id,
		"sector": sector,
		"depth": depth,
		"outcome": outcome, # "VICTORY" or "DEFEAT"
		"mutations": mutations_applied,
		"timestamp": Time.get_ticks_msec()
	}
	encounter_history.append(record)
	encounter_counts[boss_id] = encounter_counts.get(boss_id, 0) + 1


func get_history_summary() -> Array[Dictionary]:
	return encounter_history.duplicate(true)


func reset() -> void:
	encounter_history.clear()
	encounter_counts.clear()
	last_scheduled_boss_id = ""
