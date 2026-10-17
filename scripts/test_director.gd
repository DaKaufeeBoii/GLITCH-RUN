extends Node
class_name DirectorTests
## Deterministic scenario tests for BehaviorTracker and AdaptiveDirector.

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

	if all_passed:
		print("--- ALL 6 DIRECTOR SCENARIOS PASSED DETERMINISTICALLY ---")
	else:
		push_error("Some director test scenarios failed!")
	return all_passed


static func test_insufficient_data() -> bool:
	var tracker := BehaviorTracker.new()
	var director := AdaptiveDirector.new()

	# Only 5 seconds of combat time (below 12s threshold)
	tracker.total_combat_time = 5.0
	var profile := tracker.get_profile()

	assert(not profile.has_data, "Should flag insufficient data under threshold")
	var decision := director.evaluate_sector_tactics(profile, 1, 5, 5)
	assert(decision.tactic == "DEFAULT", "Director should deploy baseline when data insufficient")
	print("  [PASS] Insufficient Data Scenario")
	return true


static func test_high_mobility_scenario() -> bool:
	var tracker := BehaviorTracker.new()
	var director := AdaptiveDirector.new()

	tracker.total_combat_time = 30.0
	# Record 7 dashes within 30s (~14 dashes/min)
	for i in range(7):
		tracker.record_dash(float(i) * 4.0)

	var profile := tracker.get_profile()
	assert(profile.has_data, "Should have sufficient data")
	assert(profile.mobility > 0.65, "Mobility score should be high")

	var decision := director.evaluate_sector_tactics(profile, 1, 5, 5)
	assert(decision.tactic == "COUNTER_MOBILITY", "Should select COUNTER_MOBILITY")
	assert(decision.extra_dashers > 0, "Should spawn extra dasher counter")
	print("  [PASS] High Mobility Scenario")
	return true


static func test_ranged_camping_scenario() -> bool:
	var tracker := BehaviorTracker.new()
	var director := AdaptiveDirector.new()

	tracker.total_combat_time = 35.0
	tracker.long_range_time = 30.0
	tracker.close_range_time = 5.0

	var profile := tracker.get_profile()
	assert(profile.ranged > 0.70, "Ranged score should be high")

	var decision := director.evaluate_sector_tactics(profile, 2, 5, 5)
	assert(decision.tactic == "COUNTER_RANGED", "Should select COUNTER_RANGED")
	assert(decision.enemy_speed_mult > 1.10, "Should boost chaser speed to counter ranged camping")
	print("  [PASS] Ranged Camping Scenario")
	return true


static func test_stationary_turret_scenario() -> bool:
	var tracker := BehaviorTracker.new()
	var director := AdaptiveDirector.new()

	tracker.total_combat_time = 30.0
	tracker.total_firing_time = 20.0
	tracker.stationary_firing_time = 18.0 # 90% stationary firing
	tracker.mobile_firing_time = 2.0

	var profile := tracker.get_profile()
	assert(profile.turret > 0.65, "Turret score should be high")

	var decision := director.evaluate_sector_tactics(profile, 2, 5, 5)
	assert(decision.tactic == "COUNTER_TURRET", "Should select COUNTER_TURRET")
	assert(decision.extra_shooters > 0, "Should spawn artillery pressure")
	print("  [PASS] Stationary Turret Scenario")
	return true


static func test_tactic_cooldown() -> bool:
	var tracker := BehaviorTracker.new()
	var director := AdaptiveDirector.new()

	tracker.total_combat_time = 30.0
	for i in range(7):
		tracker.record_dash(float(i) * 4.0)
	var profile := tracker.get_profile()

	# First evaluation: triggers COUNTER_MOBILITY
	var decision1 := director.evaluate_sector_tactics(profile, 1, 5, 5)
	assert(decision1.tactic == "COUNTER_MOBILITY", "First run selects mobility counter")

	# Second consecutive evaluation: cannot pick COUNTER_MOBILITY again due to cooldown
	var decision2 := director.evaluate_sector_tactics(profile, 2, 5, 5)
	assert(decision2.tactic != "COUNTER_MOBILITY", "Cooldown should prevent identical consecutive tactic")
	print("  [PASS] Tactic Cooldown Prevention")
	return true


static func test_fairness_weight_adjustment() -> bool:
	var director := AdaptiveDirector.new()
	var initial_weight: float = director.tactic_weights["COUNTER_MOBILITY"]

	# Simulate player taking heavy damage (3 hits) during COUNTER_MOBILITY
	director.record_tactic_result("COUNTER_MOBILITY", 4)
	assert(director.tactic_weights["COUNTER_MOBILITY"] < initial_weight, "Weight should decrease after unfair damage")
	print("  [PASS] Fairness Weight Adjustment")
	return true
