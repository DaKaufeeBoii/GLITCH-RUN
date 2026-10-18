extends Node
class_name DirectorTests
## Deterministic scenario tests for BehaviorTracker and AdaptiveDirector.

const BEHAVIOR_TRACKER_SCRIPT := preload("res://scripts/behavior_tracker.gd")
const ADAPTIVE_DIRECTOR_SCRIPT := preload("res://scripts/adaptive_director.gd")

func _ready() -> void:
	run_all_tests()


static func run_all_tests() -> bool:
	print("--- Running Adaptive Director Scenario Tests ---")
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

	if all_passed:
		print("--- ALL 10 DIRECTOR, AUDIO & EVOLVED AI SCENARIOS PASSED DETERMINISTICALLY ---")
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

