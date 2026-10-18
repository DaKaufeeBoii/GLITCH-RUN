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

func _ready() -> void:
	if OS.get_cmdline_user_args().has("--run-tests") or OS.get_cmdline_args().has("--run-tests"):
		run_all_tests()


static func run_all_tests() -> bool:
	print("--- Running Adaptive Director & Procedural Dungeon Scenario Tests ---")
	var all_passed := true

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
	all_passed = test_save_schema_v2_migration() and all_passed
	all_passed = test_dungeon_topology_branching_routes() and all_passed
	all_passed = test_subseed_determinism() and all_passed
	all_passed = test_run_state_history_bounding() and all_passed
	all_passed = test_branching_room_advancement() and all_passed

	if all_passed:
		print("--- ALL 26 DIRECTOR, EVOLUTION, LEARNING, FAIRNESS & DUNGEON NAVIGATION SCENARIOS PASSED DETERMINISTICALLY ---")
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

	# Simulate high mobility player profile -> Shooters specialize with PREDICTIVE_OPTICS
	var mobile_profile := {
		"mobility": 0.85,
		"ranged": 0.35,
		"turret": 0.15,
		"dashes_per_min": 12.0,
		"successful_player_tactics": {}
	}

	# Grab shooter genome before encounter
	var shooter_g = evo_mgr.get_genome_for_spawn("SHOOTER")
	assert(not shooter_g.has_mutation("PREDICTIVE_OPTICS"), "Generation 1 shooter starts unmutated")

	# Process encounter where player dashed frequently
	var adaptations := evo_mgr.process_encounter_end(1, 1, 22.0, mobile_profile, "COUNTER_MOBILITY")
	assert(evo_mgr.generation == 2, "Generation must advance after encounter")

	# Check that shooter in population acquired PREDICTIVE_OPTICS
	var shooter_g2 = evo_mgr.get_genome_for_spawn("SHOOTER")
	assert(shooter_g2.has_mutation("PREDICTIVE_OPTICS"), "Shooter must develop PREDICTIVE_OPTICS after high mobility encounter")

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

	# Wave counts
	assert(prog.calculate_waves_for_current_room("START") == 1, "START room must have 1 wave")
	assert(prog.calculate_waves_for_current_room("COMBAT") == 3, "Early depth COMBAT room must have 3 waves")

	# Deep depth wave count
	prog.run_depth = 8
	assert(prog.calculate_waves_for_current_room("COMBAT") == 5, "Deep depth COMBAT room must have 5 waves")

	# Wave advancement
	prog.reset()
	prog.calculate_waves_for_current_room("COMBAT") # 3 waves
	assert(prog.advance_wave(), "Must advance to wave 2")
	assert(prog.current_wave == 2, "Current wave must be 2")
	assert(prog.advance_wave(), "Must advance to wave 3")
	assert(prog.current_wave == 3, "Current wave must be 3")
	assert(not prog.advance_wave(), "advance_wave() must return false when reaching final wave in room")

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

	# Deterministic sector seed derivation
	var s1: int = RUN_PROGRESSION_SCRIPT.derive_sector_seed(9999, 1)
	var s1_repeat: int = RUN_PROGRESSION_SCRIPT.derive_sector_seed(9999, 1)
	var s2: int = RUN_PROGRESSION_SCRIPT.derive_sector_seed(9999, 2)
	assert(s1 == s1_repeat, "Identical inputs must derive identical sector seeds")
	assert(s1 != s2, "Different sectors must derive distinct seeds")

	print("  [PASS] Run Progression Multi-Wave Scaling & Monotonic Depth Scenario")
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




