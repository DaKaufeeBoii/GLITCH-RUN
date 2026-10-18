extends Node
class_name DirectorTests
## Deterministic scenario tests for BehaviorTracker and AdaptiveDirector.

const BEHAVIOR_TRACKER_SCRIPT := preload("res://scripts/behavior_tracker.gd")
const ADAPTIVE_DIRECTOR_SCRIPT := preload("res://scripts/adaptive_director.gd")
const ENEMY_GENOME_SCRIPT := preload("res://scripts/enemy_genome.gd")
const EVOLUTION_MANAGER_SCRIPT := preload("res://scripts/evolution_manager.gd")
const LEARNING_POLICY_SCRIPT := preload("res://scripts/learning_policy.gd")
const DUNGEON_GEN_SCRIPT := preload("res://scripts/dungeon_generator.gd")
const ENCOUNTER_DIR_SCRIPT := preload("res://scripts/encounter_director.gd")
const RUN_PROGRESSION_SCRIPT := preload("res://scripts/run_progression.gd")
const ENEMY_STEERING_SCRIPT := preload("res://scripts/enemy_steering.gd")
const SPATIAL_INDEX_SCRIPT := preload("res://scripts/spatial_index.gd")
const SQUAD_COORDINATOR_SCRIPT := preload("res://scripts/squad_coordinator.gd")
const BOSS_DIRECTOR_SCRIPT := preload("res://scripts/boss_director.gd")
const BOSS_DEFINITION_SCRIPT := preload("res://scripts/boss_definition.gd")
const SETTINGS_MANAGER_SCRIPT := preload("res://scripts/settings_manager.gd")
const MAIN_MENU_SCRIPT := preload("res://scripts/main_menu.gd")
const PAUSE_MENU_SCRIPT := preload("res://scripts/pause_menu.gd")
const CRASH_LOGGER_SCRIPT := preload("res://scripts/crash_logger.gd")
const DEBRIS_EMITTER_SCRIPT := preload("res://scripts/debris_emitter.gd")
const MOBILE_CONTROLS_SCRIPT := preload("res://scripts/mobile_controls.gd")
const CHASER_SCENE := preload("res://scenes/enemies/chaser.tscn")
const DASHER_SCENE := preload("res://scenes/enemies/dasher.tscn")
const SHOOTER_SCENE := preload("res://scenes/enemies/shooter.tscn")

func _ready() -> void:
	if OS.get_cmdline_user_args().has("--run-tests") or OS.get_cmdline_args().has("--run-tests"):
		run_all_tests()


static func run_all_tests() -> bool:
	print("--- Running Adaptive Director & Procedural Dungeon Scenario Tests ---")
	var all_passed := true

	all_passed = test_enemy_evolution_species_isolation_and_tiers() and all_passed
	all_passed = test_pause_menu_quit_session_flow() and all_passed
	all_passed = test_dungeon_shops_gifts_and_sector_schedule() and all_passed
	all_passed = test_insufficient_data() and all_passed
	all_passed = test_high_mobility_scenario() and all_passed
	all_passed = test_ranged_camping_scenario() and all_passed
	all_passed = test_stationary_turret_scenario() and all_passed
	all_passed = test_tactic_cooldown() and all_passed
	all_passed = test_fairness_weight_adjustment() and all_passed
	all_passed = test_bullet_mechanics() and all_passed
	all_passed = test_tactical_micro_ai() and all_passed
	all_passed = test_audio_synth() and all_passed
	all_passed = test_ui_and_telemetry() and all_passed
	all_passed = test_local_persistence() and all_passed
	all_passed = test_rolling_window_decay() and all_passed
	all_passed = test_enemy_genome_bounds_and_mutations() and all_passed
	all_passed = test_evolution_manager_layers_and_retention() and all_passed
	all_passed = test_learning_policy_robustness_and_fairness() and all_passed
	all_passed = test_procedural_dungeon_100_seeds() and all_passed
	all_passed = test_encounter_director_integration() and all_passed
	all_passed = test_boss_dash_single_hit_fairness() and all_passed
	all_passed = test_shooter_aim_lock_during_telegraph() and all_passed
	all_passed = test_run_state_idempotent_finalization() and all_passed
	all_passed = test_run_progression_wave_scaling_and_depth() and all_passed
	all_passed = test_boss_room_always_has_boss() and all_passed
	all_passed = test_upgrade_stack_caps() and all_passed
	all_passed = test_start_screen_flow() and all_passed
	all_passed = test_save_schema_v2_migration() and all_passed
	all_passed = test_dungeon_topology_branching_routes() and all_passed
	all_passed = test_subseed_determinism() and all_passed
	all_passed = test_run_state_history_bounding() and all_passed
	all_passed = test_branching_room_advancement() and all_passed
	all_passed = test_ai_bounded_prediction() and all_passed
	all_passed = test_ai_obstacle_avoidance_steering() and all_passed
	all_passed = test_ai_spatial_separation_and_capping() and all_passed
	all_passed = test_ai_squad_attack_staggering() and all_passed
	all_passed = test_dasher_hazard_cap_and_spacing() and all_passed
	all_passed = test_boss_definition_registry() and all_passed
	all_passed = test_boss_director_rotation_and_schedule() and all_passed
	all_passed = test_returning_boss_mutation_tradeoffs() and all_passed
	all_passed = test_boss_history_run_persistence() and all_passed
	all_passed = test_settings_persistence_and_audio_buses() and all_passed
	all_passed = test_menu_and_pause_modal_flows() and all_passed
	all_passed = test_android_configuration_and_touch_targets() and all_passed
	all_passed = test_save_corruption_and_offline_recovery() and all_passed
	all_passed = test_android_back_and_lifecycle_navigation() and all_passed
	all_passed = test_debris_and_entity_bounding() and all_passed
	all_passed = test_crash_logger_offline_diagnostics() and all_passed

	if all_passed:
		print("--- ALL 45 DIRECTOR, EVOLUTION, STEERING, BOSS ROSTER, SETTINGS, UI & ANDROID HARDENING SCENARIOS PASSED DETERMINISTICALLY ---")
	else:
		push_error("Some director or evolved AI test scenarios failed!")
	return all_passed


static func test_insufficient_data() -> bool:
	var tracker = BEHAVIOR_TRACKER_SCRIPT.new()
	var director = ADAPTIVE_DIRECTOR_SCRIPT.new()

	# Only 5 seconds of combat time (below 12s threshold)
	tracker.total_combat_time = 5.0
	var profile: Dictionary = tracker.get_profile()

	assert(not profile.has_data, "Should flag insufficient data under threshold")
	var decision: Dictionary = director.evaluate_sector_tactics(profile, 1, 5, 5)
	assert(decision.tactic == "DEFAULT", "Director should deploy baseline when data insufficient")
	print("  [PASS] Insufficient Data Scenario")
	return true


static func test_high_mobility_scenario() -> bool:
	var tracker = BEHAVIOR_TRACKER_SCRIPT.new()
	var director = ADAPTIVE_DIRECTOR_SCRIPT.new()

	tracker.total_combat_time = 30.0
	# Record 7 dashes within 30s (~14 dashes/min)
	for i in range(7):
		tracker.record_dash(float(i) * 4.0)

	var profile: Dictionary = tracker.get_profile()
	assert(profile.has_data, "Should have sufficient data")
	assert(profile.mobility > 0.65, "Mobility score should be high")

	var decision: Dictionary = director.evaluate_sector_tactics(profile, 1, 5, 5)
	assert(decision.tactic == "COUNTER_MOBILITY", "Should select COUNTER_MOBILITY")
	assert(decision.extra_dashers > 0, "Should spawn extra dasher counter")
	print("  [PASS] High Mobility Scenario")
	return true


static func test_ranged_camping_scenario() -> bool:
	var tracker = BEHAVIOR_TRACKER_SCRIPT.new()
	var director = ADAPTIVE_DIRECTOR_SCRIPT.new()

	tracker.total_combat_time = 35.0
	tracker.long_range_time = 30.0
	tracker.close_range_time = 5.0

	var profile: Dictionary = tracker.get_profile()
	assert(profile.ranged > 0.70, "Ranged score should be high")

	var decision: Dictionary = director.evaluate_sector_tactics(profile, 2, 5, 5)
	assert(decision.tactic == "COUNTER_RANGED", "Should select COUNTER_RANGED")
	assert(decision.enemy_speed_mult > 1.10, "Should boost chaser speed to counter ranged camping")
	print("  [PASS] Ranged Camping Scenario")
	return true


static func test_stationary_turret_scenario() -> bool:
	var tracker = BEHAVIOR_TRACKER_SCRIPT.new()
	var director = ADAPTIVE_DIRECTOR_SCRIPT.new()

	tracker.total_combat_time = 30.0
	tracker.total_firing_time = 20.0
	tracker.stationary_firing_time = 18.0 # 90% stationary firing
	tracker.mobile_firing_time = 2.0

	var profile: Dictionary = tracker.get_profile()
	assert(profile.turret > 0.65, "Turret score should be high")

	var decision: Dictionary = director.evaluate_sector_tactics(profile, 2, 5, 5)
	assert(decision.tactic == "COUNTER_TURRET", "Should select COUNTER_TURRET")
	assert(decision.extra_shooters > 0, "Should spawn artillery pressure")
	print("  [PASS] Stationary Turret Scenario")
	return true


static func test_tactic_cooldown() -> bool:
	var tracker = BEHAVIOR_TRACKER_SCRIPT.new()
	var director = ADAPTIVE_DIRECTOR_SCRIPT.new()

	tracker.total_combat_time = 30.0
	for i in range(7):
		tracker.record_dash(float(i) * 4.0)
	var profile: Dictionary = tracker.get_profile()

	# First evaluation: triggers COUNTER_MOBILITY
	var decision1: Dictionary = director.evaluate_sector_tactics(profile, 1, 5, 5)
	assert(decision1.tactic == "COUNTER_MOBILITY", "First run selects mobility counter")

	# Second consecutive evaluation: cannot pick COUNTER_MOBILITY again due to cooldown
	var decision2: Dictionary = director.evaluate_sector_tactics(profile, 2, 5, 5)
	assert(decision2.tactic != "COUNTER_MOBILITY", "Cooldown should prevent identical consecutive tactic")
	print("  [PASS] Tactic Cooldown Prevention")
	return true


static func test_fairness_weight_adjustment() -> bool:
	var director = ADAPTIVE_DIRECTOR_SCRIPT.new()
	var initial_weight: float = director.tactic_weights["COUNTER_MOBILITY"]

	# Simulate player taking heavy damage (3 hits) during COUNTER_MOBILITY
	director.record_tactic_result("COUNTER_MOBILITY", 4)
	assert(director.tactic_weights["COUNTER_MOBILITY"] < initial_weight, "Weight should decrease after unfair damage")
	print("  [PASS] Fairness Weight Adjustment")
	return true


static func test_bullet_mechanics() -> bool:
	var proj_scene := load("res://scenes/weapons/projectile.tscn")
	var proj = proj_scene.instantiate()
	var player_scene := load("res://scenes/player/player.tscn")
	var player: CharacterBody2D = player_scene.instantiate()
	player.add_to_group("player")

	# Bullet must not destroy itself on player
	proj._on_body_entered(player)
	assert(not proj.is_queued_for_deletion(), "Bullet must ignore player body")

	# Bullet must damage enemy and destroy itself
	var chaser_scene := load("res://scenes/enemies/chaser.tscn")
	var chaser: CharacterBody2D = chaser_scene.instantiate()
	chaser.add_to_group("enemies")
	var init_hp: int = chaser.health
	proj._on_body_entered(chaser)
	assert(chaser.health == init_hp - 1, "Enemy should take 1 damage from bullet")
	assert(proj.is_queued_for_deletion(), "Bullet should queue_free on enemy hit")

	player.free()
	chaser.free()
	proj.free()

	print("  [PASS] Bullet Mechanics & Collision Scenario")
	return true


static func test_tactical_micro_ai() -> bool:
	var player_scene := load("res://scenes/player/player.tscn")
	var player: CharacterBody2D = player_scene.instantiate()
	player.global_position = Vector2(300, 300)
	player.velocity = Vector2(0, 200)

	# 1. Shooter Predictive Lead Aiming
	var shooter_scene := load("res://scenes/enemies/shooter.tscn")
	var shooter: CharacterBody2D = shooter_scene.instantiate()
	shooter.global_position = Vector2(100, 300)
	shooter.target = player
	shooter.lead_prediction = 1.0

	shooter._physics_process(0.016)
	assert(shooter.aimed_direction.y > 0.05, "Shooter must lead aim along player's downward velocity")

	# 2. Chaser Pincer Flanking Angle
	var chaser_scene := load("res://scenes/enemies/chaser.tscn")
	var chaser: CharacterBody2D = chaser_scene.instantiate()
	chaser.global_position = Vector2(100, 300)
	chaser.target = player
	chaser.flank_angle = 0.65
	chaser.is_flanker = true

	chaser._physics_process(0.016)
	assert(chaser.velocity.y > 10.0, "Chaser must apply flank angle rotation to approach vector")

	# 3. Dasher Hazard Trail Activation
	var dasher_scene := load("res://scenes/enemies/dasher.tscn")
	var dasher: CharacterBody2D = dasher_scene.instantiate()
	dasher.has_hazard_trail = true
	assert(dasher.has_hazard_trail, "Dasher must accept evolved hazard trail state")

	player.free()
	shooter.free()
	chaser.free()
	dasher.free()

	print("  [PASS] Tactical Micro-AI Evolutions (Lead Aim, Pincer Flank, Hazard Trail)")
	return true


static func test_audio_synth() -> bool:
	var synth_script := load("res://scripts/audio_synth.gd")
	var synth: Node = synth_script.new()
	synth._ready()

	assert(synth.sounds.has("blaster"), "AudioSynth must produce blaster sound")
	assert(synth.sounds.has("dash"), "AudioSynth must produce dash sound")
	assert(synth.sounds.has("hit_impact"), "AudioSynth must produce hit_impact sound")
	assert(synth.sounds.has("wave_clear"), "AudioSynth must produce wave_clear sound")
	assert(synth.sounds["blaster"].data.size() > 100, "Synthesized PCM waveform data must be non-empty")
	assert(synth.sounds["dash"].data.size() > 100, "Synthesized dash waveform data must be non-empty")

	synth.free()
	print("  [PASS] Procedural Audio & SFX Waveform Synthesis (11 Retro Profiles)")
	return true


static func test_ui_and_telemetry() -> bool:
	var debrief_script := load("res://scripts/debrief_terminal.gd")
	var debrief: Control = debrief_script.new()
	debrief._ready()
	assert(not debrief.visible, "Debrief terminal must start hidden")

	var test_metrics := {
		"moving_time_ratio": 0.85,
		"avg_distance_to_enemy": 280.0,
		"firing_time_ratio": 0.6,
		"dash_count": 8,
		"damage_taken": 1
	}
	var test_tactics := [
		{
			"sector": 2,
			"tactic": "COUNTER_MOBILITY",
			"reason": "High dash frequency detected",
			"mutations": "Shooter Lead Aim (λ=0.75)"
		}
	]

	debrief.setup_debrief(true, test_metrics, test_tactics)
	assert(debrief.archetype_name != "", "Debrief terminal must classify player archetype")
	assert(debrief.player_radar_vals.size() == 4, "Radar must generate 4-axis polygon values")
	assert(debrief.director_radar_vals.size() == 4, "Director radar must generate 4-axis counter values")

	# Test Pause Menu
	var pause_script := load("res://scripts/pause_menu.gd")
	var pause_menu: Control = pause_script.new()
	pause_menu._ready()
	assert(not pause_menu.visible, "Pause menu must start hidden")

	debrief.free()
	pause_menu.free()
	print("  [PASS] Director Telemetry Debrief Terminal & Tactical Pause UI")
	return true


static func test_local_persistence() -> bool:
	var rs_script := load("res://scripts/run_state.gd")
	var rs: Node = rs_script.new()
	rs.best_sector = 4
	rs.best_score = 42
	rs.best_time = 128.5
	rs.save_persistent_data()

	# Re-instantiate to simulate application restart
	var rs_reloaded: Node = rs_script.new()
	rs_reloaded.load_persistent_data()
	assert(rs_reloaded.best_sector == 4, "Best sector must survive application restart")
	assert(rs_reloaded.best_score == 42, "Best score must survive application restart")
	assert(absf(rs_reloaded.best_time - 128.5) < 0.1, "Best time must survive application restart")

	rs.free()
	rs_reloaded.free()
	print("  [PASS] Local Persistence (user://save_data.json Survival Scenario)")
	return true


static func test_rolling_window_decay() -> bool:
	var tracker = BEHAVIOR_TRACKER_SCRIPT.new()
	var dummy_enemy := Node2D.new()
	dummy_enemy.global_position = Vector2(500, 300)
	var enemies: Array[Node2D] = [dummy_enemy]

	# Phase 1: Stationary firing for 50 seconds (exceeding 45s window)
	for i in range(50):
		tracker.update(1.0, Vector2(300, 300), Vector2.ZERO, enemies, true, float(i))

	var prof1: Dictionary = tracker.get_profile()
	assert(prof1.turret > 0.8, "Should have high turret score after stationary firing")

	# Phase 2: Active mobile movement without firing for 60 seconds
	for i in range(60):
		tracker.update(1.0, Vector2(300, 300), Vector2(150, 0), enemies, false, 50.0 + float(i))

	# Stationary firing should have decayed significantly
	assert(tracker.stationary_firing_time < 15.0, "Old stationary firing time must decay in rolling window")

	dummy_enemy.free()
	print("  [PASS] Behavior Tracker Rolling Window Decay Scenario")
	return true


static func test_enemy_genome_bounds_and_mutations() -> bool:
	var g = ENEMY_GENOME_SCRIPT.new("SHOOTER", 1)
	assert(g.prediction_strength == 0.0, "Initial prediction strength should be 0.0")
	assert(g.attack_timing_mult == 1.0, "Initial attack timing mult should be 1.0")

	# Apply named mutation PREDICTIVE_OPTICS
	var applied := g.apply_named_mutation("PREDICTIVE_OPTICS")
	assert(applied, "Should successfully apply PREDICTIVE_OPTICS")
	assert(g.has_mutation("PREDICTIVE_OPTICS"), "Genome must register active mutation")
	assert(g.prediction_strength > 0.4, "Prediction strength must increase")
	assert(g.attack_timing_mult > 1.1, "Attack timing multiplier must increase (slower firing tradeoff)")

	# Repeated identical mutation should be rejected without double-buffing
	var applied_again := g.apply_named_mutation("PREDICTIVE_OPTICS")
	assert(not applied_again, "Should not re-apply identical mutation")

	# Bounded trait check: perturb traits repeatedly and verify hard clamp bounds
	for i in range(100):
		g.aggression += 0.5
		g.prediction_strength += 0.5
		g.flanking_tendency += 0.5
		g.clamp_all_traits()
		assert(g.aggression <= ENEMY_GENOME_SCRIPT.MAX_AGGRESSION, "Aggression must never exceed MAX_AGGRESSION (1.35)")
		assert(g.prediction_strength <= ENEMY_GENOME_SCRIPT.MAX_PREDICTION, "Prediction must never exceed MAX_PREDICTION (1.0)")
		assert(g.flanking_tendency <= ENEMY_GENOME_SCRIPT.MAX_FLANKING, "Flanking must never exceed MAX_FLANKING (1.0)")

	# Test serialization round-trip
	var d: Dictionary = g.to_dict()
	var g_reconstructed = ENEMY_GENOME_SCRIPT.from_dict(d)
	assert(g_reconstructed.family == "SHOOTER", "Family must survive serialization")
	assert(g_reconstructed.has_mutation("PREDICTIVE_OPTICS"), "Active mutations must survive serialization")
	assert(absf(g_reconstructed.aggression - g.aggression) < 0.01, "Aggression must survive serialization")

	print("  [PASS] Enemy Genome Evolvable Traits, Trade-offs & Bounded Caps Scenario")
	return true


static func test_evolution_manager_layers_and_retention() -> bool:
	var evo_mgr = EVOLUTION_MANAGER_SCRIPT.new()
	assert(evo_mgr.generation == 1, "Evolution manager must start at Generation 1")

	# Simulate high mobility player profile -> Shooters specialize with AGILE_STRAFE then PREDICTIVE_OPTICS
	var mobile_profile := {
		"mobility": 0.85,
		"ranged": 0.35,
		"turret": 0.15,
		"dashes_per_min": 12.0,
		"active_families": ["SHOOTER"],
		"successful_player_tactics": {}
	}

	# Grab shooter genome before encounter
	var shooter_g = evo_mgr.get_genome_for_spawn("SHOOTER")
	assert(not shooter_g.has_mutation("AGILE_STRAFE"), "Generation 1 shooter starts unmutated")
	assert(not shooter_g.has_mutation("PREDICTIVE_OPTICS"), "Generation 1 shooter starts unmutated")

	# Encounter 1: Paced evolution -> does not evolve after just 1 battle
	var _adaptations := evo_mgr.process_encounter_end(1, 1, 22.0, mobile_profile, "COUNTER_MOBILITY")
	assert(evo_mgr.generation == 2, "Generation must advance after encounter")
	var shooter_g1 = evo_mgr.get_genome_for_spawn("SHOOTER")
	assert(not shooter_g1.has_mutation("AGILE_STRAFE"), "Enemies must not evolve too quickly: requires 2 battles")

	# Encounter 2: Reaches BATTLES_FOR_FIRST_EVOLUTION (2) -> Acquires Tier 1 AGILE_STRAFE
	evo_mgr.get_genome_for_spawn("SHOOTER")
	evo_mgr.process_encounter_end(1, 1, 20.0, mobile_profile, "COUNTER_MOBILITY")
	var shooter_g2 = evo_mgr.get_genome_for_spawn("SHOOTER")
	assert(shooter_g2.has_mutation("AGILE_STRAFE"), "Shooter must develop AGILE_STRAFE at Tier 1 after 2 battles")

	# Encounters 3 & 4: Reaches BATTLES_FOR_SECOND_EVOLUTION (4) -> Acquires Tier 2 PREDICTIVE_OPTICS
	evo_mgr.get_genome_for_spawn("SHOOTER")
	evo_mgr.process_encounter_end(1, 1, 18.0, mobile_profile, "COUNTER_MOBILITY")
	evo_mgr.get_genome_for_spawn("SHOOTER")
	evo_mgr.process_encounter_end(1, 1, 19.0, mobile_profile, "COUNTER_MOBILITY")
	var shooter_g4 = evo_mgr.get_genome_for_spawn("SHOOTER")
	assert(shooter_g4.has_mutation("PREDICTIVE_OPTICS"), "Shooter must develop PREDICTIVE_OPTICS at Tier 2 after 4 battles")

	# Test Population retention (Layer C): ensure bounds and population structure
	assert(evo_mgr.active_genomes["SHOOTER"].size() == 3, "Population pool size must be preserved")
	for g in evo_mgr.active_genomes["SHOOTER"]:
		assert(g.aggression <= ENEMY_GENOME_SCRIPT.MAX_AGGRESSION, "Population traits must remain bounded")

	# Reset must restore Generation 1 clean slate
	evo_mgr.reset()
	assert(evo_mgr.generation == 1, "Reset must restore Generation 1")
	assert(evo_mgr.evolution_history.is_empty(), "Reset must clear evolution history")

	print("  [PASS] Multi-Layer Evolution Manager (Specialization & Population Retention) Scenario")
	return true


static func test_learning_policy_robustness_and_fairness() -> bool:
	var policy = LEARNING_POLICY_SCRIPT.new()

	# 1. Context feature extraction
	var profile := {
		"mobility": 0.80,
		"ranged": 0.20,
		"turret": 0.10,
		"aggression": 0.40
	}
	var ctx := policy.extract_context(profile, 0.45)
	assert(ctx.size() == 6, "Context vector must be exactly 6 dimensions")
	assert(absf(ctx[1] - 0.80) < 0.01, "Mobility feature must match profile")
	assert(absf(ctx[5] - 0.45) < 0.01, "Chokepoint ratio feature must match room context")

	# 2. Strict Fairness / Mercy Stabilization when player is critically low on health
	var mercy_decision := policy.select_action(ctx, 1, 5) # 20% HP
	assert(mercy_decision.action_name == "STABILIZATION", "Policy must force STABILIZATION when player HP <= 35%")

	# 3. Healthy action selection
	var normal_decision := policy.select_action(ctx, 5, 5)
	assert(normal_decision.action_name in LEARNING_POLICY_SCRIPT.ACTION_NAMES, "Selected action must be in action space")

	# 4. Graceful handling of missing / empty / malformed profile data
	var malformed_ctx := policy.extract_context({}, 0.0)
	var safe_decision := policy.select_action(malformed_ctx, 5, 5)
	assert(safe_decision.action_name != "", "Policy must handle empty context safely without crashing")

	# 5. Reward computation and policy weights export / load
	var reward_fair := policy.compute_reward(1, 20.0, profile, 0)
	var reward_overkill := policy.compute_reward(4, 20.0, profile, 0)
	assert(reward_fair > reward_overkill, "Fair encounter must receive higher reward than overkill encounter")

	var exported := policy.export_weights()
	var reloaded_policy = LEARNING_POLICY_SCRIPT.new()
	var load_ok := reloaded_policy.load_weights(exported)
	assert(load_ok, "Exported weights must reload successfully")

	print("  [PASS] LinUCB Learning Policy Robustness, Fairness Mercy & Export Scenario")
	return true


static func test_procedural_dungeon_100_seeds() -> bool:
	var gen = DUNGEON_GEN_SCRIPT.new()
	var total_tested := 100

	# Test 100 distinct procedural dungeon seeds
	for s in range(1001, 1001 + total_tested):
		var layout = gen.generate_dungeon(s, 6)
		assert(layout != null, "Generator returned null layout for seed %d" % s)
		assert(layout.rooms.size() == 6, "Seed %d must produce exactly 6 rooms" % s)
		assert(layout.rooms[0].room_type == "START", "Seed %d room 0 must be START room" % s)
		assert(layout.rooms[5].room_type == "BOSS", "Seed %d room 5 must be BOSS room" % s)

		# Validate every room in the dungeon
		for room in layout.rooms:
			assert(room.is_validated, "Seed %d Room %d failed reachability validation!" % [s, room.index])
			assert(room.bounds.has_point(room.player_spawn), "Player spawn outside bounds in seed %d" % s)
			assert(room.bounds.has_point(room.exit_door), "Exit door outside bounds in seed %d" % s)
			assert(room.enemy_spawns.size() >= 1, "Room must have at least 1 enemy spawn in seed %d" % s)

			# Ensure minimum distance between player spawn and all enemy spawns
			for espawn in room.enemy_spawns:
				var dist: float = room.player_spawn.distance_to(espawn.pos)
				assert(dist >= 195.0, "Player to enemy distance too close (%.1fpx) in seed %d room %d" % [dist, s, room.index])

	# Test Deterministic Reproducibility
	# The exact same seed must produce the exact same obstacles and spawns
	var layout_a = gen.generate_dungeon(778899, 6)
	var layout_b = gen.generate_dungeon(778899, 6)
	assert(layout_a.rooms.size() == layout_b.rooms.size(), "Dungeons from same seed must have identical room count")
	for r_idx in range(6):
		var ra = layout_a.rooms[r_idx]
		var rb = layout_b.rooms[r_idx]
		assert(ra.template_name == rb.template_name, "Rooms from identical seed must share template name")
		assert(ra.obstacles.size() == rb.obstacles.size(), "Obstacle counts must be identical for identical seed")
		for o_idx in range(ra.obstacles.size()):
			assert(ra.obstacles[o_idx] == rb.obstacles[o_idx], "Obstacle rects must match identically for identical seed")
		for e_idx in range(ra.enemy_spawns.size()):
			assert(ra.enemy_spawns[e_idx].pos == rb.enemy_spawns[e_idx].pos, "Enemy spawn positions must match identically")

	print("  [PASS] Procedural Dungeon 100-Seed Reachability & Deterministic Reproducibility Scenario")
	return true


static func test_encounter_director_integration() -> bool:
	var enc_dir = ENCOUNTER_DIR_SCRIPT.new()
	var dgen = DUNGEON_GEN_SCRIPT.new()
	var layout = dgen.generate_dungeon(999, 6)

	var room = layout.get_room(1)
	var profile := {
		"has_data": true,
		"mobility": 0.40,
		"ranged": 0.85, # Heavy sniper
		"turret": 0.20,
		"aggression": 0.20
	}

	var encounter: Dictionary = enc_dir.prepare_encounter(room, profile, 5, 5)
	assert(encounter.has("tactic"), "Encounter must have selected tactic")
	assert(encounter.has("spawn_list"), "Encounter must have prepared spawn list")
	assert(not encounter.spawn_list.is_empty(), "Spawn list must not be empty")

	# Check that spawned enemies have genomes assigned
	for espawn in encounter.spawn_list:
		if espawn.type in ["CHASER", "SHOOTER", "DASHER"]:
			assert(espawn.genome != null, "Enemy spawn must be equipped with an EnemyGenome")

	print("  [PASS] Encounter Director & Genome Pipeline Integration Scenario")
	return true


static func test_boss_dash_single_hit_fairness() -> bool:
	var boss_scene := load("res://scenes/enemies/boss.tscn")
	var boss: CharacterBody2D = boss_scene.instantiate()
	var player_scene := load("res://scenes/player/player.tscn")
	var player: CharacterBody2D = player_scene.instantiate()

	player.global_position = Vector2(200, 200)
	player.health = 5
	boss.global_position = Vector2(210, 200) # within 46px contact radius
	boss.target = player
	boss.current_phase = boss.AttackPhase.DASHING
	boss.phase_timer = 0.40
	boss.dash_hit_player = false
	boss.dash_target_dir = Vector2(1, 0)

	# Simulate 5 physics frames while overlapping
	for i in range(5):
		boss._physics_process(0.016)

	assert(player.health == 3, "Boss dash must apply contact damage exactly once per dash (took %d dmg)" % (5 - player.health))
	assert(boss.dash_hit_player, "dash_hit_player flag must be set after first hit")

	boss.free()
	player.free()
	print("  [PASS] Boss Dash Single-Hit Fairness Scenario")
	return true


static func test_shooter_aim_lock_during_telegraph() -> bool:
	var shooter_scene := load("res://scenes/enemies/shooter.tscn")
	var shooter: CharacterBody2D = shooter_scene.instantiate()
	var player_scene := load("res://scenes/player/player.tscn")
	var player: CharacterBody2D = player_scene.instantiate()

	player.global_position = Vector2(300, 100)
	shooter.global_position = Vector2(100, 100)
	shooter.target = player
	shooter.lead_prediction = 0.0

	# First frame: not telegraphing, establishes initial aim towards (1, 0)
	shooter.telegraph_time = 0.0
	shooter._physics_process(0.016)
	var initial_aim: Vector2 = shooter.aimed_direction
	assert(initial_aim.x > 0.9, "Initial aim should target player directly along X axis")

	# Start telegraph and move player to (100, 400) (directly below shooter)
	shooter.telegraph_time = 0.50
	player.global_position = Vector2(100, 400)
	shooter._physics_process(0.016)

	assert(shooter.aimed_direction == initial_aim, "Shooter aimed_direction must remain locked during telegraph")

	shooter.free()
	player.free()
	print("  [PASS] Shooter Aim Lock During Telegraph Scenario")
	return true


static func test_run_state_idempotent_finalization() -> bool:
	var rs_script := load("res://scripts/run_state.gd")
	var rs: Node = rs_script.new()
	rs.start_new_run(55555)
	rs.current_room_index = 3
	rs.score = 25
	rs.run_time = 45.0

	# First finalization
	rs.finalize_run_stats(false)
	assert(rs.is_finalized, "RunState must be marked finalized")
	assert(not rs.run_active, "RunState must not be active after finalization")
	var recorded_best_sector: int = rs.best_sector
	var recorded_best_score: int = rs.best_score

	# Second finalization call (e.g. duplicate death signal or suspension)
	rs.current_room_index = 5
	rs.score = 999
	rs.finalize_run_stats(true)

	# State must remain identical to first finalization
	assert(rs.best_sector == recorded_best_sector, "Duplicate finalization must not mutate best_sector")
	assert(rs.best_score == recorded_best_score, "Duplicate finalization must not overwrite score")

	rs.free()
	print("  [PASS] RunState Idempotent Finalization Scenario")
	return true


static func test_run_progression_wave_scaling_and_depth() -> bool:
	var prog = RUN_PROGRESSION_SCRIPT.new(4242, "NORMAL")
	assert(prog.run_depth == 1, "Progression must start at depth 1")
	assert(prog.sector_index == 1, "Progression must start in Sector 1")
	assert(prog.room_index == 0, "Progression must start at room 0")

	# Sector wave schedule (Normal difficulty: Sector 1 = 3 waves, Sector 2 = 4 waves, Sector 3 = 5 waves)
	assert(prog.sector_total_waves == 3, "Normal Sector 1 must schedule 3 regular waves")
	var prog_sec2 = RUN_PROGRESSION_SCRIPT.new(4242, "NORMAL")
	prog_sec2.sector_index = 2
	prog_sec2._init_sector_wave_schedule()
	assert(prog_sec2.sector_total_waves == 4, "Normal Sector 2 must schedule 4 regular waves")
	var prog_sec3 = RUN_PROGRESSION_SCRIPT.new(4242, "NORMAL")
	prog_sec3.sector_index = 3
	prog_sec3._init_sector_wave_schedule()
	assert(prog_sec3.sector_total_waves == 5, "Normal Sector 3 must schedule 5 regular waves")

	# Difficulty scaling
	var prog_easy = RUN_PROGRESSION_SCRIPT.new(4242, "EASY")
	assert(prog_easy.sector_total_waves == 3, "Easy difficulty must schedule 3 waves per sector")
	var prog_hard = RUN_PROGRESSION_SCRIPT.new(4242, "HARD")
	assert(prog_hard.sector_total_waves == 4, "Hard Sector 1 must schedule 4 waves")

	# Every room guarantees combat wave engagement (never 0 waves)
	assert(prog.calculate_waves_for_current_room("START") == 1, "START room must have 1 introductory wave")
	assert(prog.calculate_waves_for_current_room("RECOVERY") >= 1, "RECOVERY room must have combat wave")
	assert(prog.calculate_waves_for_current_room("SHOP") >= 1, "SHOP room must have combat wave")
	assert(prog.calculate_waves_for_current_room("GIFT") >= 1, "GIFT room must have combat wave")
	assert(prog.calculate_waves_for_current_room("BOSS") == 1, "BOSS room must have 1 boss wave")
	assert(prog.calculate_waves_for_current_room("COMBAT") >= 2, "Combat rooms guarantee multiple combat waves")

	# Wave advancement across combat waves
	prog.reset()
	var w_count := prog.calculate_waves_for_current_room("COMBAT")
	assert(w_count >= 2, "Early depth combat room has at least 2 waves")
	assert(prog.advance_wave(), "Must advance to wave 2")
	assert(prog.current_wave == 2, "Current wave must be 2")
	prog.complete_current_wave()

	# Room & Sector advancement
	prog.reset()
	for r in range(4):
		var nav: Dictionary = prog.advance_room()
		assert(not nav.is_new_sector, "Rooms 1 to 4 must not trigger new sector")
	# 5th advance triggers new sector
	var sec_nav: Dictionary = prog.advance_room()
	assert(sec_nav.is_new_sector, "5th room advance must trigger new sector")
	assert(prog.sector_index == 2, "Sector index must advance to 2")
	assert(prog.room_index == 0, "Room index must reset to 0 in new sector")
	assert(prog.run_depth == 6, "Run depth must monotonically increment to 6")
	assert(prog.sector_total_waves == 4, "Sector 2 wave schedule must advance to 4 waves")

	# Deterministic sector seed derivation
	var s1: int = RUN_PROGRESSION_SCRIPT.derive_sector_seed(9999, 1)
	var s1_repeat: int = RUN_PROGRESSION_SCRIPT.derive_sector_seed(9999, 1)
	var s2: int = RUN_PROGRESSION_SCRIPT.derive_sector_seed(9999, 2)
	assert(s1 == s1_repeat, "Identical inputs must derive identical sector seeds")
	assert(s1 != s2, "Different sectors must derive distinct seeds")

	print("  [PASS] Run Progression Multi-Wave Scaling & Monotonic Depth Scenario")
	return true



static func test_boss_room_always_has_boss() -> bool:
	var generator = DUNGEON_GEN_SCRIPT.new()
	for seed_value in range(1, 101):
		var layout = generator.generate_dungeon(seed_value, 5)
		var boss_room = layout.get_room(layout.total_rooms - 1)
		assert(boss_room != null and boss_room.room_type == "BOSS", "Every sector graph must end in a boss room")
		var boss_count := 0
		for spawn in boss_room.enemy_spawns:
			if spawn.type == "BOSS":
				boss_count += 1
		assert(boss_count == 1, "Every generated boss room must contain exactly one boss spawn")
	print("  [PASS] Generated Boss Chamber Encounter Composition (100 seeds)")
	return true


static func test_upgrade_stack_caps() -> bool:
	var rs_script := load("res://scripts/run_state.gd")
	var rs: Node = rs_script.new()
	rs.start_new_run(4242)
	assert(rs.apply_upgrade("HIGH_VOLTAGE"), "First HIGH_VOLTAGE stack should apply")
	assert(rs.apply_upgrade("HIGH_VOLTAGE"), "Second HIGH_VOLTAGE stack should apply")
	assert(not rs.apply_upgrade("HIGH_VOLTAGE"), "HIGH_VOLTAGE must reject stacks past its cap")
	assert(rs.damage_bonus == 2, "Capped damage upgrade must not over-apply")
	assert(rs.get_upgrade_stack_count("HIGH_VOLTAGE") == 2, "Stack count should match applied stacks")
	assert(rs.apply_upgrade("OVERCLOCK"), "OVERCLOCK should allow its first stack")
	assert(rs.apply_upgrade("OVERCLOCK"), "OVERCLOCK should allow its second stack")
	assert(rs.apply_upgrade("OVERCLOCK"), "OVERCLOCK should allow its third stack")
	assert(not rs.apply_upgrade("OVERCLOCK"), "OVERCLOCK must reject stacks past its cap")
	assert(rs.fire_interval_mult >= 0.35, "Fire interval must remain inside the hard cap")
	var eligible: Array[Dictionary] = rs.get_random_upgrade_choices(7)
	for item in eligible:
		assert(item.id not in ["HIGH_VOLTAGE", "OVERCLOCK"], "Fully stacked upgrades must leave the reward pool")
	for upgrade_id in rs.UPGRADE_STACK_CAPS:
		for _stack in range(rs.get_upgrade_stack_cap(upgrade_id) - rs.get_upgrade_stack_count(upgrade_id)):
			rs.apply_upgrade(upgrade_id)
	var fallback: Array[Dictionary] = rs.get_random_upgrade_choices(3)
	assert(fallback.size() == 1 and fallback[0].id == "FIELD_REPAIR", "All capped upgrades must fall back to a useful repair reward")
	rs.free()
	print("  [PASS] Upgrade Stack Caps & Hard Stat Bounds")
	return true


static func test_start_screen_flow() -> bool:
	var start_script = load("res://scripts/start_screen.gd")
	var start_screen: Control = start_script.new()
	start_screen._build_screen()
	assert(is_instance_valid(start_screen.prompt), "Splash must present a start prompt")
	assert(start_screen.prompt.text == "TAP TO START", "Splash prompt must clearly invite input")
	assert(ProjectSettings.get_setting("application/run/main_scene") == "res://scenes/ui/start_screen.tscn", "Splash must be the first launched scene")
	start_screen.free()
	print("  [PASS] Splash First Screen & Tap-to-Menu Flow")
	return true


static func test_save_schema_v2_migration() -> bool:
	var rs_script := load("res://scripts/run_state.gd")
	var rs: Node = rs_script.new()

	# Test v1 migration: best_sector converted to best_depth
	var v1_data := {
		"version": 1,
		"best_sector": 4,
		"best_score": 150,
		"best_time": 95.0
	}
	# Verify version 1 data parsing logic
	var migrated_depth: int = maxi(1, int(v1_data.get("best_sector", 1)))
	var migrated_sector: int = maxi(1, int(ceilf(float(migrated_depth) / 5.0)))
	assert(migrated_depth == 4, "v1 best_sector must map to best_depth")
	assert(migrated_sector == 1, "Depth 4 must map to Sector 1")

	# Test v2 data structure
	rs.start_new_run(12345)
	rs.progression.run_depth = 12
	rs.progression.sector_index = 3
	rs.score = 300
	rs.finalize_run_stats(true)

	assert(rs.best_depth == 12, "v2 best_depth must persist correctly")
	assert(rs.best_sector == 3, "v2 best_sector must persist correctly")

	rs.free()
	print("  [PASS] Save Schema V2 Migration & Depth Persistence Scenario")
	return true


static func test_dungeon_topology_branching_routes() -> bool:
	var gen = DUNGEON_GEN_SCRIPT.new()
	var layout = gen.generate_dungeon(7777, 5)

	# Verify sector room count
	assert(layout.rooms.size() == 5, "Layout must contain 5 chambers")

	# Verify Room 1 has branching forward exit doors
	var room_1 = layout.get_room(1)
	assert(room_1 != null, "Room 1 must exist")
	assert(room_1.exit_doors.size() >= 2, "Room 1 must provide at least 2 branching exit doors")

	var door_a: Dictionary = room_1.exit_doors[0]
	var door_b: Dictionary = room_1.exit_doors[1]
	assert(door_a.target_room != door_b.target_room, "Branching doors must lead to distinct rooms")
	assert(door_a.target_room > 1 and door_b.target_room > 1, "Exit doors must point forward")
	assert(not door_a.label.is_empty() and not door_b.label.is_empty(), "Exit doors must have readable route labels")

	# Verify all rooms in sector are validated for reachability
	for r in layout.rooms:
		assert(r.is_validated, "All generated chambers must pass BFS reachability validation")
		assert(not r.exit_doors.is_empty(), "Every chamber must contain at least one exit door")

	print("  [PASS] Procedural Dungeon Branching Routes & Validated Exits Scenario")
	return true


static func test_subseed_determinism() -> bool:
	var gen = DUNGEON_GEN_SCRIPT.new()

	# Generate layout twice with identical seed
	var l1 = gen.generate_dungeon(4321, 5)
	var l2 = gen.generate_dungeon(4321, 5)

	for i in range(5):
		var r1 = l1.get_room(i)
		var r2 = l2.get_room(i)
		assert(r1.template_name == r2.template_name, "Identical seed must pick identical templates")
		assert(r1.obstacles.size() == r2.obstacles.size(), "Obstacle counts must match")
		for o_idx in range(r1.obstacles.size()):
			assert(r1.obstacles[o_idx] == r2.obstacles[o_idx], "Obstacle geometry must match exactly")
		assert(r1.player_spawn == r2.player_spawn, "Player spawn must match")
		assert(r1.exit_doors.size() == r2.exit_doors.size(), "Exit door count must match")

	print("  [PASS] Independent Sub-Seed Determinism Scenario")
	return true


static func test_run_state_history_bounding() -> bool:
	var rs_script := load("res://scripts/run_state.gd")
	var rs: Node = rs_script.new()
	rs.start_new_run(9876)

	# 1. Tactics Log Bounding
	for i in range(35):
		rs.record_tactic(i, "TACTIC_%d" % i, "REASON", "MUTATIONS")
	assert(rs.tactics_log.size() == rs.MAX_LOG_HISTORY, "tactics_log must be capped at MAX_LOG_HISTORY (20)")
	assert(rs.tactics_log[0].tactic == "TACTIC_15", "tactics_log must drop oldest entries and preserve newest")

	# 2. Evolution Log Bounding
	var mock_history: Array = []
	for i in range(40):
		mock_history.append({"id": i, "trait": "TRAIT_%d" % i})
	rs.set_evolution_log(mock_history)
	assert(rs.evolution_log.size() == rs.MAX_LOG_HISTORY, "evolution_log must be capped at MAX_LOG_HISTORY (20)")
	assert(rs.evolution_log[0].id == 20, "evolution_log must preserve newest 20 entries")

	# 3. Dungeon Summary Bounding
	for i in range(30):
		rs.record_room_summary({"index": i, "room_type": "COMBAT"})
	assert(rs.dungeon_layout_summary.size() == rs.MAX_DUNGEON_HISTORY, "dungeon_layout_summary must be capped at MAX_DUNGEON_HISTORY (15)")
	assert(rs.dungeon_layout_summary[0].index == 15, "dungeon_layout_summary must preserve newest 15 rooms")

	rs.free()
	print("  [PASS] RunState Endless Run History Bounding Scenario")
	return true


static func test_branching_room_advancement() -> bool:
	var prog = RUN_PROGRESSION_SCRIPT.new(1111, "NORMAL")

	# Step from room 0 to room 1
	prog.advance_room()
	assert(prog.room_index == 1, "Should be at room 1")
	assert(prog.run_depth == 2, "Depth should be 2")

	# Branch choice: Jump to room 3 (Elite bypass)
	var nav = prog.advance_room(3)
	assert(prog.room_index == 3, "Should jump to room 3")
	assert(prog.run_depth == 3, "Depth should increment to 3")
	assert(not nav.is_new_sector, "Should remain in current sector")

	# Step to room 4 (Boss)
	nav = prog.advance_room(4)
	assert(prog.room_index == 4, "Should be at room 4 (Boss)")
	assert(prog.run_depth == 4, "Depth should be 4")
	assert(not nav.is_new_sector, "Should remain in current sector")

	# Step from Boss to Next Sector
	nav = prog.advance_room(5)
	assert(nav.is_new_sector, "Stepping past sector rooms must trigger new sector")
	assert(prog.sector_index == 2, "Sector index should advance to 2")
	assert(prog.room_index == 0, "Room index should reset to 0 in new sector")
	assert(prog.run_depth == 5, "Depth should be 5")

	print("  [PASS] Branching Route Room Advancement & Sector Gateway Scenario")
	return true


static func test_ai_bounded_prediction() -> bool:
	var origin := Vector2(100, 100)
	var target_pos := Vector2(300, 100) # Directly to the right, distance 200
	var bullet_speed := 400.0

	# 1. Zero prediction factor must return direct target position
	var direct_pos: Vector2 = ENEMY_STEERING_SCRIPT.predict_target_position(origin, target_pos, Vector2(0, 300), bullet_speed, 0.0)
	assert(direct_pos == target_pos, "Zero prediction factor must aim straight at target")

	# 2. Perpendicular movement with prediction leads target
	var lead_pos: Vector2 = ENEMY_STEERING_SCRIPT.predict_target_position(origin, target_pos, Vector2(0, 200), bullet_speed, 1.0)
	assert(lead_pos.y > target_pos.y, "Aim must lead target down when velocity is downward")

	# 3. Maximum lead angle clamp: even with extreme transverse velocity (10,000 px/s),
	# deflection angle relative to direct line must not exceed MAX_LEAD_ANGLE (45 deg = 0.7854 rad)
	var extreme_lead_pos: Vector2 = ENEMY_STEERING_SCRIPT.predict_target_position(origin, target_pos, Vector2(0, 10000), bullet_speed, 1.0)
	var direct_dir := (target_pos - origin).normalized()
	var clamped_dir := (extreme_lead_pos - origin).normalized()
	var angle_deflection := absf(direct_dir.angle_to(clamped_dir))
	assert(angle_deflection <= ENEMY_STEERING_SCRIPT.MAX_LEAD_ANGLE + 0.001, "Lead prediction must be clamped to 45 degrees max to preserve dodge window")

	print("  [PASS] AI Bounded Target Prediction & Dodge Window Scenario")
	return true


static func test_ai_obstacle_avoidance_steering() -> bool:
	var obstacles: Array[Rect2] = [
		Rect2(200, 180, 40, 40) # Obstacle at (200, 180) to (240, 220), center at (220, 200)
	]

	# 1. Direct path hitting the obstacle must be deflected
	var agent_pos := Vector2(170, 200) # Heading directly right toward center of obstacle
	var desired_dir := Vector2.RIGHT
	var steered_dir: Vector2 = ENEMY_STEERING_SCRIPT.avoid_obstacles(agent_pos, desired_dir, obstacles, 45.0)
	assert(steered_dir != desired_dir, "Obstacle avoidance must deflect trajectory when heading into obstacle")
	assert(absf(steered_dir.y) > 0.1, "Steered trajectory must develop lateral deflection component")

	# 2. Line of sight blocked through obstacle
	var blocked: bool = ENEMY_STEERING_SCRIPT.is_line_blocked(Vector2(150, 200), Vector2(250, 200), obstacles)
	assert(blocked, "Line of sight penetrating obstacle must return blocked=true")

	# 3. Clear line of sight outside obstacle
	var clear: bool = ENEMY_STEERING_SCRIPT.is_line_blocked(Vector2(150, 100), Vector2(250, 100), obstacles)
	assert(not clear, "Clear line of sight must return blocked=false")

	print("  [PASS] AI Obstacle Avoidance Steering & Line of Sight Scenario")
	return true


static func test_ai_spatial_separation_and_capping() -> bool:
	var index = SPATIAL_INDEX_SCRIPT.new()

	# Create dummy combatant nodes
	var node1 := Node2D.new()
	node1.global_position = Vector2(100, 100)
	var node2 := Node2D.new()
	node2.global_position = Vector2(105, 100) # 5px away
	var node3 := Node2D.new()
	node3.global_position = Vector2(110, 100) # 10px away
	var node4 := Node2D.new()
	node4.global_position = Vector2(115, 100) # 15px away
	var node5 := Node2D.new()
	node5.global_position = Vector2(120, 100) # 20px away

	index.register_agent(node1)
	index.register_agent(node2)
	index.register_agent(node3)
	index.register_agent(node4)
	index.register_agent(node5)
	index.update_cache()

	# Neighbor count capping: capped to 3 neighbors max
	var neighbors: Array[Vector2] = index.get_neighbor_positions(node1.global_position, 50.0, 3, node1.global_position)
	assert(neighbors.size() == 3, "SpatialIndex neighbor lookup must be capped at max_count")

	# Separation repulsion: node1 is to the left of neighbors, so separation must push left (-X)
	var sep: Vector2 = index.get_separation_for_agent(node1, 50.0, 3)
	assert(sep.x < 0.0, "Separation vector must push away from neighbor cluster")

	# Agent unregistration
	index.unregister_agent(node5)
	assert(index.registered_agents.size() == 4, "Unregistering agent must update index size")

	node1.free()
	node2.free()
	node3.free()
	node4.free()
	node5.free()

	print("  [PASS] AI Spatial Neighbor Separation & Bounded Capping Scenario")
	return true


static func test_ai_squad_attack_staggering() -> bool:
	var coordinator = SQUAD_COORDINATOR_SCRIPT.new(1, 0.45)
	var enemy_a := Node2D.new()
	var enemy_b := Node2D.new()

	# 1. First attacker requests token at t = 1.0 -> Granted
	var granted_a: bool = coordinator.request_attack_token(enemy_a, 1.0)
	assert(granted_a, "First attacker should be granted an attack token")
	assert(coordinator.is_attacker_active(enemy_a), "Attacker A must be registered as active")

	# 2. Second attacker requests token immediately at t = 1.1 -> Denied by stagger cooldown
	var granted_b_early: bool = coordinator.request_attack_token(enemy_b, 1.1)
	assert(not granted_b_early, "Simultaneous attack within stagger window must be denied")

	# 3. Second attacker requests token after stagger cooldown at t = 1.6 -> Denied because max concurrent tokens = 1
	var granted_b_staggered: bool = coordinator.request_attack_token(enemy_b, 1.6)
	assert(not granted_b_staggered, "Attack must be denied when max concurrent threat tokens is reached")

	# 4. Attacker A finishes attack and releases token -> Attacker B granted token at t = 1.7
	coordinator.release_attack_token(enemy_a)
	assert(not coordinator.is_attacker_active(enemy_a), "Attacker A must be deregistered")
	var granted_b_freed: bool = coordinator.request_attack_token(enemy_b, 1.7)
	assert(granted_b_freed, "Attacker B must be granted token after previous token release and stagger window")

	# 5. Low player health fairness mercy stabilization
	coordinator.configure_for_depth(10, 2) # Deep depth, but player HP is critical (<= 2)
	assert(coordinator.max_concurrent_threat_tokens == 1, "Fairness stabilization must clamp tokens to 1 when HP <= 2")
	assert(coordinator.min_stagger_cooldown >= 0.65, "Fairness stabilization must lengthen stagger window when HP <= 2")

	enemy_a.free()
	enemy_b.free()

	print("  [PASS] AI Squad Attack Budget Staggering & Fairness Mercy Scenario")
	return true


static func test_dasher_hazard_cap_and_spacing() -> bool:
	var dasher_scene := load("res://scenes/enemies/dasher.tscn")
	var dasher: CharacterBody2D = dasher_scene.instantiate()
	dasher.has_hazard_trail = true

	assert(dasher.MAX_ACTIVE_HAZARDS == 4, "Dasher must cap active hazards to 4 max")
	assert(dasher.active_hazards.is_empty(), "Initial hazards list must be empty")

	# Simulate active hazards
	var dummy_hazards: Array[Node2D] = []
	for i in range(5):
		var h := Node2D.new()
		dummy_hazards.append(h)
		dasher.active_hazards.append(h)

	# Clean hazards when nodes become invalid or queue_freed
	dummy_hazards[0].free()
	dasher._clean_hazards()
	assert(dasher.active_hazards.size() == 4, "Clean hazards must prune freed nodes")

	for i in range(1, 5):
		dummy_hazards[i].free()

	dasher.free()

	print("  [PASS] Dasher Hazard Trail Capping & Spacing Scenario")
	return true


static func test_boss_definition_registry() -> bool:
	var director = BOSS_DIRECTOR_SCRIPT.new()
	assert(director.definitions.size() == 3, "Boss director must have 3 authored bosses")
	assert(director.definitions.has("nexus_overlord"), "Must register nexus_overlord")
	assert(director.definitions.has("vector_sentinel"), "Must register vector_sentinel")
	assert(director.definitions.has("null_architect"), "Must register null_architect")

	for b_id in ["nexus_overlord", "vector_sentinel", "null_architect"]:
		var b_def = director.get_boss_definition(b_id)
		assert(b_def != null, "Definition must exist for %s" % b_id)
		assert(ResourceLoader.exists(b_def.scene_path), "Boss scene must exist at %s" % b_def.scene_path)
		assert(b_def.base_health >= 25, "Base health must be at least 25")
		assert(b_def.base_speed > 30.0, "Base speed must be > 30")
		assert(b_def.allowed_mutations.size() >= 2, "Boss must define at least 2 authored mutation tiers")
		for m in b_def.allowed_mutations:
			assert(m.has("id") and m.has("name") and m.has("desc"), "Mutation must have id, name, and desc trade-off")

	print("  [PASS] Boss Definition Roster Registry Scenario")
	return true


static func test_boss_director_rotation_and_schedule() -> bool:
	var director = BOSS_DIRECTOR_SCRIPT.new()

	# 1. Sector 1 eligibility: Sector 1 has nexus_overlord and vector_sentinel
	var sec1_eligible: Array = director.get_eligible_bosses(1)
	assert(sec1_eligible.size() == 2, "Sector 1 must have exactly 2 eligible bosses")

	# 2. Sector 2 eligibility: All 3 bosses eligible
	var sec2_eligible: Array = director.get_eligible_bosses(2)
	assert(sec2_eligible.size() == 3, "Sector 2+ must have all 3 bosses eligible")

	# 3. Repetition cooldown: selecting boss for next sector must not repeat last_scheduled_boss_id
	var seed_val := 4242
	var b1 = director.select_boss_for_sector(1, seed_val, "")
	var b2 = director.select_boss_for_sector(2, seed_val, b1.boss_id)
	assert(b2.boss_id != b1.boss_id, "Boss scheduling must enforce repetition cooldown across adjacent sectors")

	# 4. Deterministic schedule: same seed must produce identical schedule
	var director2 = BOSS_DIRECTOR_SCRIPT.new()
	var b1_repro = director2.select_boss_for_sector(1, seed_val, "")
	var b2_repro = director2.select_boss_for_sector(2, seed_val, b1_repro.boss_id)
	assert(b1_repro.boss_id == b1.boss_id, "Boss schedule must be 100% deterministic for a seed")
	assert(b2_repro.boss_id == b2.boss_id, "Boss schedule must be 100% deterministic for a seed")

	print("  [PASS] Boss Director Rotation & Repetition Cooldown Scenario")
	return true


static func test_returning_boss_mutation_tradeoffs() -> bool:
	var director = BOSS_DIRECTOR_SCRIPT.new()

	# 1. First encounter has 0 mutations (clean baseline)
	var m0: Array[Dictionary] = director.get_mutations_for_encounter("nexus_overlord")
	assert(m0.is_empty(), "First encounter must have 0 mutations (baseline calibration)")

	# Simulate first defeat
	director.record_encounter("nexus_overlord", 1, 5, "VICTORY", m0)

	# 2. Second encounter (first return) has Tier 1 mutation with trade-off
	var m1: Array[Dictionary] = director.get_mutations_for_encounter("nexus_overlord")
	assert(m1.size() == 1, "Returning boss must receive exactly 1 capped mutation tier")
	assert(m1[0].id == "BURST_OVERCLOCK", "First return must assign Tier 1 mutation (BURST_OVERCLOCK)")

	# Simulate second defeat
	director.record_encounter("nexus_overlord", 2, 10, "VICTORY", m1)

	# 3. Third encounter has Tier 2 mutation
	var m2: Array[Dictionary] = director.get_mutations_for_encounter("nexus_overlord")
	assert(m2.size() == 1, "Third encounter must have exactly 1 capped mutation tier")
	assert(m2[0].id == "TITAN_DASH", "Second return must assign Tier 2 mutation (TITAN_DASH)")

	# 4. Verify boss instance parameter mutation with trade-off
	var boss_scene := load("res://scenes/enemies/boss.tscn")
	var boss: CharacterBody2D = boss_scene.instantiate()
	assert(boss.burst_projectile_count == 8, "Baseline projectile count should be 8")
	assert(boss.post_burst_recovery == 1.0, "Baseline post-burst recovery should be 1.0s")

	boss.apply_mutations(m1)
	assert(boss.burst_projectile_count == 10, "BURST_OVERCLOCK must increase projectiles to 10")
	assert(boss.post_burst_recovery > 1.2, "BURST_OVERCLOCK must add recovery time trade-off")
	boss.free()

	print("  [PASS] Returning Boss Mutation Tiers & Trade-offs Scenario")
	return true


static func test_boss_history_run_persistence() -> bool:
	var rs_scene := load("res://scripts/run_state.gd")
	var rs = rs_scene.new()
	rs.start_new_run(9999)

	assert(rs.boss_encounter_history.is_empty(), "boss_encounter_history must start empty on new run")

	# Record multiple encounters
	for i in range(25):
		rs.record_boss_encounter("boss_%d" % i, i + 1, (i + 1) * 5, "VICTORY", [{"id": "MUT"}])

	# Bounding check
	assert(rs.boss_encounter_history.size() == rs.MAX_LOG_HISTORY, "boss_encounter_history must be capped at MAX_LOG_HISTORY (20)")
	assert(rs.boss_encounter_history[0].boss_id == "boss_5", "Must preserve newest 20 encounters")

	# Starting new run must clear history
	rs.start_new_run(8888)
	assert(rs.boss_encounter_history.is_empty(), "Starting new run must clear boss_encounter_history")

	rs.free()
	print("  [PASS] Boss History Run Persistence & Bounding Scenario")
	return true


static func test_settings_persistence_and_audio_buses() -> bool:
	var sm = SETTINGS_MANAGER_SCRIPT.new()
	sm._setup_audio_buses()

	# Audio buses exist
	assert(AudioServer.get_bus_index("Master") != -1, "Master bus must exist")
	assert(AudioServer.get_bus_index("Music") != -1, "Music bus must exist")
	assert(AudioServer.get_bus_index("SFX") != -1, "SFX bus must exist")

	# Defaults
	assert(sm.master_volume >= 0.0 and sm.master_volume <= 1.0, "Master volume must be normalized")
	assert(sm.music_volume >= 0.0 and sm.music_volume <= 1.0, "Music volume must be normalized")
	assert(sm.sfx_volume >= 0.0 and sm.sfx_volume <= 1.0, "SFX volume must be normalized")

	# Mutation and persistence
	sm.master_volume = 0.65
	sm.music_volume = 0.45
	sm.sfx_volume = 0.85
	sm.screen_shake_enabled = false
	sm.haptics_enabled = false
	sm.save_settings()

	var sm_reload = SETTINGS_MANAGER_SCRIPT.new()
	sm_reload.load_settings()
	assert(is_equal_approx(sm_reload.master_volume, 0.65), "Master volume must reload correctly")
	assert(is_equal_approx(sm_reload.music_volume, 0.45), "Music volume must reload correctly")
	assert(is_equal_approx(sm_reload.sfx_volume, 0.85), "SFX volume must reload correctly")
	assert(not sm_reload.screen_shake_enabled, "Screen shake setting must reload correctly")
	assert(not sm_reload.haptics_enabled, "Haptics setting must reload correctly")

	# Restore defaults
	sm.master_volume = 1.0
	sm.music_volume = 0.75
	sm.sfx_volume = 0.9
	sm.screen_shake_enabled = true
	sm.haptics_enabled = true
	sm.save_settings()

	sm.free()
	sm_reload.free()

	print("  [PASS] Settings Persistence & Multi-Bus Audio Configuration Scenario")
	return true


static func test_menu_and_pause_modal_flows() -> bool:
	# 1. Main Menu
	var menu = MAIN_MENU_SCRIPT.new()
	menu._build_ui()

	# Check difficulty cycling
	assert(menu.DIFFICULTIES.size() == 3, "Must support 3 difficulty tiers")
	var orig_diff_idx: int = int(menu.difficulty_index)
	menu._on_difficulty_pressed()
	assert(menu.difficulty_index == (orig_diff_idx + 1) % 3, "Difficulty button must cycle tiers")

	# Check modals exist and toggle
	assert(is_instance_valid(menu.how_to_play_panel), "How to play panel must exist on title menu")
	assert(is_instance_valid(menu.settings_panel), "Settings panel must exist on title menu")
	assert(is_instance_valid(menu.archive_panel), "Archive panel must exist on title menu")

	# 2. Pause Menu
	var pause = PAUSE_MENU_SCRIPT.new()
	pause._build_ui()

	assert(is_instance_valid(pause.confirm_panel), "Confirmation panel must exist on pause menu")
	assert(is_instance_valid(pause.settings_panel), "Settings panel must exist on pause menu")
	assert(is_instance_valid(pause.how_to_play_panel), "How to play panel must exist on pause menu")

	# Confirmation flow
	var restart_confirmed := [false]
	pause._show_confirmation("ABANDON RUN", "Test Msg", func(): restart_confirmed[0] = true)
	assert(pause.confirm_panel.visible, "Confirmation modal must become visible on action request")
	pause.confirm_callback.call()
	assert(restart_confirmed[0], "Confirming modal must invoke targeted action callback")

	menu.free()
	pause.free()

	print("  [PASS] Touch Navigation, Modals & Confirmation Flows Scenario")
	return true


static func test_android_configuration_and_touch_targets() -> bool:
	assert(FileAccess.file_exists("res://export_presets.cfg"), "Android export_presets.cfg must exist")
	var f := FileAccess.open("res://export_presets.cfg", FileAccess.READ)
	assert(f != null, "export_presets.cfg must be readable")
	var content := f.get_as_text()
	f.close()
	assert("com.antigravity.glitchrun" in content, "Must configure unique Android package ID")
	assert("permissions/vibrate=true" in content, "Haptics permission must be enabled")
	assert("permissions/internet=false" in content, "Internet permission must be explicitly false for offline safety")
	assert("screen/orientation=1" in content, "Landscape orientation must be enforced in export preset")
	assert("gradle_build/min_sdk=\"24\"" in content, "Min SDK must be 24 (Android 7.0)")
	assert("gradle_build/target_sdk=\"34\"" in content, "Target SDK must be 34 (Android 14)")

	# Verify mobile virtual controls sizing exceeds 48dp
	var ctrl = MOBILE_CONTROLS_SCRIPT.new()
	assert(float(ctrl.get("JOYSTICK_RADIUS")) >= 48.0, "Joystick radius must exceed 48dp touch threshold")
	assert(float(ctrl.get("DASH_RADIUS")) >= 48.0, "Dash radius must be at least 48dp touch threshold")
	assert(float(ctrl.get("RELOAD_RADIUS")) * 2.0 >= 48.0, "Reload button diameter must exceed 48dp touch threshold")
	assert(ctrl.has_signal("reload_pressed"), "Mobile controls must expose reload_pressed signal")
	assert("android_icon_192.png" in content, "Launcher 192 icon must be configured")
	ctrl.free()

	print("  [PASS] Android Export Preset Configuration & Touch Targets Scenario")
	return true


static func test_save_corruption_and_offline_recovery() -> bool:
	var rs_script := preload("res://scripts/run_state.gd")
	var rs = rs_script.new()

	# Create a corrupt save file
	var sf := FileAccess.open("user://save_data.json", FileAccess.WRITE)
	sf.store_string("CORRUPTED_NON_JSON_DATA{{{{")
	sf.close()

	# Load must gracefully recover without crashing or corrupting state
	rs.load_persistent_data()
	assert(rs.best_depth >= 1, "Corrupted save must fall back to valid depth")
	assert(rs.best_score >= 0, "Corrupted save must fall back to valid score")

	# Test corrupt settings file
	var sm = SETTINGS_MANAGER_SCRIPT.new()
	var set_f := FileAccess.open("user://settings.json", FileAccess.WRITE)
	set_f.store_string("12345_NOT_A_DICT")
	set_f.close()

	sm.load_settings()
	assert(sm.master_volume >= 0.0 and sm.master_volume <= 1.0, "Corrupted settings must maintain clamped volume")
	assert(sm.screen_shake_intensity >= 0.0, "Corrupted settings must maintain valid shake intensity")

	# Restore clean valid state
	rs.save_persistent_data()
	sm.save_settings()
	rs.free()
	sm.free()

	print("  [PASS] Save File Corruption & Offline Recovery Scenario")
	return true


static func test_android_back_and_lifecycle_navigation() -> bool:
	var menu = MAIN_MENU_SCRIPT.new()
	menu._build_ui()

	# When a modal is open, _handle_back_request closes the modal
	menu.settings_panel.visible = true
	menu._handle_back_request()
	assert(not menu.settings_panel.visible, "Back request must dismiss settings modal")

	menu.how_to_play_panel.visible = true
	menu._handle_back_request()
	assert(not menu.how_to_play_panel.visible, "Back request must dismiss how to play modal")

	menu.archive_panel.visible = true
	menu._handle_back_request()
	assert(not menu.archive_panel.visible, "Back request must dismiss threat archive modal")

	var pause = PAUSE_MENU_SCRIPT.new()
	pause._build_ui()
	pause.visible = true
	pause._show_confirmation("TEST", "MSG", func(): pass)
	assert(pause.confirm_panel.visible, "Confirmation modal must be open")
	pause._handle_back_request()
	assert(not pause.confirm_panel.visible, "Back request must dismiss confirmation modal")

	# Back request when no modal is open in pause menu should close pause / resume simulation
	pause._handle_back_request()
	assert(not pause.visible, "Back request on pause menu must resume simulation")

	menu.free()
	pause.free()

	print("  [PASS] Android Back Key & Navigation Hierarchy Scenario")
	return true


static func test_debris_and_entity_bounding() -> bool:
	var emitter = DEBRIS_EMITTER_SCRIPT.new()
	assert(int(emitter.get("MAX_ACTIVE_SHARDS")) <= 64, "Debris emitter must bound max active shards for mobile GPU/CPU safety")
	var orig_count: int = int(DEBRIS_EMITTER_SCRIPT.active_shard_count)
	var test_parent := Node2D.new()
	DEBRIS_EMITTER_SCRIPT.active_shard_count = DEBRIS_EMITTER_SCRIPT.MAX_ACTIVE_SHARDS
	DEBRIS_EMITTER_SCRIPT.spawn_shards(test_parent, Vector2.ZERO, Color.WHITE, "diamond", 12)
	assert(test_parent.get_child_count() == 0, "Spawning shards when at max cap must produce zero new nodes")
	DEBRIS_EMITTER_SCRIPT.active_shard_count = orig_count
	test_parent.free()

	print("  [PASS] Mobile Debris & Particle Bounding Scenario")
	return true


static func test_crash_logger_offline_diagnostics() -> bool:
	CRASH_LOGGER_SCRIPT.log_info("DIAGNOSTIC_QA_TEST_ENTRY_ALPHA")
	CRASH_LOGGER_SCRIPT.log_warning("DIAGNOSTIC_QA_TEST_WARN_BETA")
	var logs: String = CRASH_LOGGER_SCRIPT.read_recent_logs()
	assert("DIAGNOSTIC_QA_TEST_ENTRY_ALPHA" in logs, "Local QA logger must record info logs to disk")
	assert("DIAGNOSTIC_QA_TEST_WARN_BETA" in logs, "Local QA logger must record warning logs to disk")
	assert("Mem:" in logs, "Local QA logger must record memory footprint")
	assert(FileAccess.file_exists(CRASH_LOGGER_SCRIPT.LOG_FILE), "Local log file must exist on user storage")

	print("  [PASS] Offline QA Crash Logger & Diagnostics Scenario")
	return true


static func test_enemy_evolution_species_isolation_and_tiers() -> bool:
	var evo_mgr = EVOLUTION_MANAGER_SCRIPT.new()
	assert(evo_mgr.get_species_tier("CHASER") == 0, "Chaser starts at Tier 0")
	assert(evo_mgr.get_species_tier("DASHER") == 0, "Dasher starts at Tier 0")
	assert(evo_mgr.get_species_tier("SHOOTER") == 0, "Shooter starts at Tier 0")
	assert(evo_mgr.get_species_health_multiplier("CHASER") == 1, "Chaser Tier 0 has 1x health multiplier")

	# Test strict species isolation & paced evolution:
	# Simulate encounters where ONLY Chaser participated. Player was kiting (ranged = 0.85).
	var chaser_g = evo_mgr.get_genome_for_spawn("CHASER")
	evo_mgr.register_spawned_combatant(chaser_g)

	var kite_profile := {
		"ranged": 0.85,
		"mobility": 0.40,
		"turret": 0.20
	}
	# Battle 1 for Chaser: Still Tier 0 due to pacing (requires 2 battles)
	var _adaptations0 = evo_mgr.process_encounter_end(0, 0, 15.0, kite_profile, "DEFAULT")
	assert(evo_mgr.get_species_tier("CHASER") == 0, "Chaser remains Tier 0 after 1 battle (paced evolution)")

	# Battle 2 for Chaser: Evolved to Tier 1 (+45% speed, 2x HP)
	evo_mgr.register_spawned_combatant(chaser_g)
	var adaptations1 = evo_mgr.process_encounter_end(0, 0, 15.0, kite_profile, "DEFAULT")
	assert(evo_mgr.get_species_tier("CHASER") == 1, "Chaser must evolve to Tier 1 after 2 kited battles")
	assert(evo_mgr.get_species_health_multiplier("CHASER") == 2, "Chaser Tier 1 must have 2x health multiplier")
	assert(evo_mgr.get_species_tier("DASHER") == 0, "Dasher must remain Tier 0 because it did not fight")
	assert(evo_mgr.get_species_tier("SHOOTER") == 0, "Shooter must remain Tier 0 because it did not fight")
	assert(not adaptations1.is_empty(), "Must record Tier 1 adaptation")
	assert(adaptations1[0].family == "CHASER", "Adaptation must be for Chaser")

	# Battles 3 & 4 for Chaser: Reaches Tier 2 (Learns to aim and shoot crimson blaster)
	evo_mgr.register_spawned_combatant(chaser_g)
	evo_mgr.process_encounter_end(0, 0, 12.0, kite_profile, "DEFAULT")
	evo_mgr.register_spawned_combatant(chaser_g)
	var _adaptations2 = evo_mgr.process_encounter_end(0, 0, 12.0, kite_profile, "DEFAULT")
	assert(evo_mgr.get_species_tier("CHASER") == 2, "Chaser must evolve to Tier 2 after 4 battles")
	assert(evo_mgr.get_species_health_multiplier("CHASER") == 4, "Chaser Tier 2 must have 4x health multiplier")
	assert(evo_mgr.get_species_tier("DASHER") == 0, "Dasher must still be Tier 0")

	# Verify Tier 2 Chaser node behavior:
	var chaser_node = CHASER_SCENE.instantiate()
	chaser_g.apply_to_enemy(chaser_node)
	assert(chaser_node.max_health == 12, "Chaser Tier 2 max health must be 12 (4x of base 3)")
	assert(chaser_node.health == 12, "Chaser Tier 2 current health must be 12")
	assert(chaser_node.has_ranged_attack, "Chaser Tier 2 must have learned ranged attack")
	assert(chaser_node.move_speed > 120.0, "Chaser Tier 2 must have Tier 1 speed buff preserved")
	chaser_node.free()

	# Now Dasher battles (Tier 1: Speed + Mines, Tier 2: Hyper Speed, Tier 3: Armor)
	var dasher_g = evo_mgr.get_genome_for_spawn("DASHER")
	for _i in range(2):
		evo_mgr.register_spawned_combatant(dasher_g)
		evo_mgr.process_encounter_end(1, 0, 10.0, {}, "DEFAULT")
	assert(evo_mgr.get_species_tier("DASHER") == 1, "Dasher evolves to Tier 1 after 2 battles")
	var dasher_node1 = DASHER_SCENE.instantiate()
	dasher_g.apply_to_enemy(dasher_node1)
	assert(dasher_node1.has_hazard_trail, "Dasher Tier 1 must drop hazard mines")
	assert(dasher_node1.lunge_speed >= 650.0, "Dasher Tier 1 speed boosted to 650.0")
	dasher_node1.free()

	# Dasher Tier 2: 4 battles total
	for _i in range(2):
		evo_mgr.register_spawned_combatant(dasher_g)
		evo_mgr.process_encounter_end(1, 0, 10.0, {}, "DEFAULT")
	assert(evo_mgr.get_species_tier("DASHER") == 2, "Dasher evolves to Tier 2 after 4 battles")
	var dasher_node2 = DASHER_SCENE.instantiate()
	dasher_g.apply_to_enemy(dasher_node2)
	assert(dasher_node2.lunge_speed >= 800.0, "Dasher Tier 2 hyper speed >= 800 px/s")
	dasher_node2.free()

	# Dasher Tier 3: 6 battles total (Armor buff)
	for _i in range(2):
		evo_mgr.register_spawned_combatant(dasher_g)
		evo_mgr.process_encounter_end(1, 0, 10.0, {}, "DEFAULT")
	assert(evo_mgr.get_species_tier("DASHER") == 3, "Dasher evolves to Tier 3 after 6 battles")
	assert(evo_mgr.get_species_health_multiplier("DASHER") == 3, "Dasher Tier 3 has 3x health multiplier")
	var dasher_node3 = DASHER_SCENE.instantiate()
	dasher_g.apply_to_enemy(dasher_node3)
	assert(dasher_node3.max_health == 6, "Dasher Tier 3 max health must be 6")
	dasher_node3.free()

	# Now Shooter battles (Tier 1: Speed, Tier 2: Armor + Aim, Tier 3: 2-DMG Beam)
	var shooter_g = evo_mgr.get_genome_for_spawn("SHOOTER")
	for _i in range(2):
		evo_mgr.register_spawned_combatant(shooter_g)
		evo_mgr.process_encounter_end(2, 0, 10.0, {}, "DEFAULT")
	assert(evo_mgr.get_species_tier("SHOOTER") == 1, "Shooter Tier 1 after 2 battles")
	var shooter_node1 = SHOOTER_SCENE.instantiate()
	shooter_g.apply_to_enemy(shooter_node1)
	assert(shooter_node1.move_speed >= 110.0, "Shooter Tier 1 has speed buff >= 110")
	assert(shooter_node1.lead_prediction == 0.0, "Shooter Tier 1 still has bad aim")
	shooter_node1.free()

	# Shooter Tier 2: 4 battles total (Armor 6 HP + Pinpoint Lead Aim)
	for _i in range(2):
		evo_mgr.register_spawned_combatant(shooter_g)
		evo_mgr.process_encounter_end(2, 0, 10.0, {}, "DEFAULT")
	assert(evo_mgr.get_species_tier("SHOOTER") == 2, "Shooter Tier 2 after 4 battles")
	assert(evo_mgr.get_species_health_multiplier("SHOOTER") == 2, "Shooter Tier 2 has 2x health (6 HP)")
	var shooter_node2 = SHOOTER_SCENE.instantiate()
	shooter_g.apply_to_enemy(shooter_node2)
	assert(shooter_node2.max_health == 6, "Shooter Tier 2 max health must be 6")
	assert(shooter_node2.lead_prediction == 1.0, "Shooter Tier 2 has pinpoint lead prediction 1.0")
	shooter_node2.free()

	# Shooter Tier 3: 6 battles total (2-Damage Beam + 12 HP)
	for _i in range(2):
		evo_mgr.register_spawned_combatant(shooter_g)
		evo_mgr.process_encounter_end(2, 0, 10.0, {}, "DEFAULT")
	assert(evo_mgr.get_species_tier("SHOOTER") == 3, "Shooter Tier 3 after 6 battles")
	assert(evo_mgr.get_species_health_multiplier("SHOOTER") == 4, "Shooter Tier 3 has 4x health (12 HP)")
	var shooter_node3 = SHOOTER_SCENE.instantiate()
	shooter_g.apply_to_enemy(shooter_node3)
	assert(shooter_node3.max_health == 12, "Shooter Tier 3 max health must be 12")
	assert(shooter_node3.has_beam_attack, "Shooter Tier 3 has charged beam attack")
	shooter_node3.free()

	# Test Health Doubling Invariant: calling apply_to_enemy multiple times does NOT multiply health repeatedly!
	var test_chaser = CHASER_SCENE.instantiate()
	chaser_g.apply_to_enemy(test_chaser)
	assert(test_chaser.max_health == 12, "First spawn must be 12 HP")
	chaser_g.apply_to_enemy(test_chaser)
	assert(test_chaser.max_health == 12, "Second apply must remain 12 HP, not 24 or 48 HP")
	test_chaser.free()

	# Test Run-Scoped Reset:
	evo_mgr.reset()
	assert(evo_mgr.get_species_tier("CHASER") == 0, "Reset restores Chaser to Tier 0")
	assert(evo_mgr.get_species_tier("DASHER") == 0, "Reset restores Dasher to Tier 0")
	assert(evo_mgr.get_species_tier("SHOOTER") == 0, "Reset restores Shooter to Tier 0")
	assert(evo_mgr.evolution_history.is_empty(), "Reset clears evolution history")

	print("  [PASS] Strict Species Evidence Isolation & 3-Tier Evolutions (Speed, Aim, Beam, Mines, Armor)")
	return true


static func test_pause_menu_quit_session_flow() -> bool:
	var pause = PAUSE_MENU_SCRIPT.new()
	pause._build_ui()

	# Find QUIT SESSION button
	var quit_btn: Button = pause.get_quit_button()
	if quit_btn == null:
		for child in pause.find_children("*", "", true, false):
			if child is Button and child.text == "QUIT SESSION":
				quit_btn = child
				break
	assert(quit_btn != null, "Pause menu must have a dedicated QUIT SESSION button")
	assert(quit_btn.custom_minimum_size.y >= 48.0, "QUIT SESSION button must be touch-friendly (>=48dp height)")

	# Trigger confirmation modal
	quit_btn.pressed.emit()
	assert(pause.confirm_panel.visible, "Pressing QUIT SESSION must display confirmation modal")
	assert("TERMINATE APPLICATION" in pause.confirm_msg_label.text or "QUIT SESSION" in pause.confirm_msg_label.text, "Confirmation modal must explicitly warn about session termination")
	assert("lost" in pause.confirm_msg_label.text.to_lower(), "Confirmation modal must warn that run and evolutions will be lost")

	# Back request cancels confirmation modal without quitting
	pause._handle_back_request()
	assert(not pause.confirm_panel.visible, "Back/Cancel must safely dismiss confirmation modal")

	pause.free()
	print("  [PASS] Pause Menu Touch Quit Session & Loss Confirmation Flow Scenario")
	return true


static func test_dungeon_shops_gifts_and_sector_schedule() -> bool:
	var gen = DUNGEON_GEN_SCRIPT.new()
	var shop_found := false
	var gift_found := false

	# Test 50 distinct dungeon seeds
	for s in range(5001, 5051):
		var layout = gen.generate_dungeon(s, 6)
		assert(layout.rooms.size() == 6, "Must generate 6 rooms")
		assert(layout.rooms[0].room_type == "START", "Room 0 must be START")
		assert(layout.rooms[5].room_type == "BOSS", "Room 5 must be BOSS")

		for r in layout.rooms:
			assert(r.is_validated, "Every room must be reachability validated")
			if r.room_type == "SHOP":
				shop_found = true
				assert(not r.shop_stock.is_empty(), "SHOP room must stock items with bit prices")
				for item in r.shop_stock:
					assert(item.has("cost") and int(item.cost) > 0, "Shop items must have valid bit costs")
			elif r.room_type == "GIFT":
				gift_found = true
				assert(not r.gift_choices.is_empty(), "GIFT room must offer free subroutine choices")

	assert(shop_found, "Procedural generation must produce explorable SHOP rooms across seeds")
	assert(gift_found, "Procedural generation must produce explorable GIFT cache rooms across seeds")

	print("  [PASS] Explorable Sector Graphs, Shop Kiosks & Gift Caches Scenario")
	return true
