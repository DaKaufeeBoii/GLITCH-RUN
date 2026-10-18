extends RefCounted
class_name AdaptiveDirector
## Analyzes player combat profile to evolve enemy micro-tactics: predictive aiming, pincer flanking, and hazard trails.

var last_tactic := ""
var tactic_history: Array[String] = []

# Dynamic fairness weights: lower when a tactic leads to excessive player damage
var tactic_weights: Dictionary = {
	"COUNTER_MOBILITY": 1.0,
	"COUNTER_RANGED": 1.0,
	"COUNTER_TURRET": 1.0
}


func reset() -> void:
	last_tactic = ""
	tactic_history.clear()
	tactic_weights["COUNTER_MOBILITY"] = 1.0
	tactic_weights["COUNTER_RANGED"] = 1.0
	tactic_weights["COUNTER_TURRET"] = 1.0


func evaluate_sector_tactics(profile: Dictionary, room_index: int, current_hp: int, max_hp: int) -> Dictionary:
	# Default baseline (no adaptation for Sector 1 or insufficient observation data)
	if room_index == 0 or not profile.get("has_data", false):
		return _make_default_result("STANDARD DEPLOYMENT", "Observing combat subroutines...")

	# 1. Fairness / Mercy Check: If player is critically damaged or suffering high damage rate
	var hp_ratio := float(current_hp) / float(max_hp)
	if hp_ratio <= 0.35 or profile.get("damage_per_min", 0.0) > 6.0:
		last_tactic = "STABILIZATION"
		tactic_history.append("STABILIZATION")
		return {
			"tactic": "STABILIZATION",
			"banner_title": "DIRECTOR PROTOCOL // COMBAT STABILIZATION",
			"banner_sub": "Tactical mutations suspended • Telegraph windows widened +30%",
			"enemy_speed_mult": 0.88,
			"enemy_telegraph_mult": 1.30,
			"extra_chasers": 0,
			"extra_dashers": 0,
			"extra_shooters": 0,
			"has_hazard_trail": false,
			"pincer_flanking": false,
			"shooter_lead": 0.0
		}

	# 2. Score potential counter-tactics based on profile metrics & fairness weights
	var candidate_scores: Dictionary = {}

	# Mobility candidate
	if profile.mobility > 0.58 and last_tactic != "COUNTER_MOBILITY":
		candidate_scores["COUNTER_MOBILITY"] = (profile.mobility - 0.50) * tactic_weights["COUNTER_MOBILITY"]

	# Ranged / Camping candidate
	if profile.ranged > 0.58 and last_tactic != "COUNTER_RANGED":
		candidate_scores["COUNTER_RANGED"] = (profile.ranged - 0.50) * tactic_weights["COUNTER_RANGED"]

	# Stationary Turret candidate
	if profile.turret > 0.50 and last_tactic != "COUNTER_TURRET":
		candidate_scores["COUNTER_TURRET"] = (profile.turret - 0.40) * tactic_weights["COUNTER_TURRET"]

	# If no specific profile is dominant, maintain balanced combat
	if candidate_scores.is_empty():
		return _make_default_result("BALANCED SURGE", "Tactical baseline maintained.")

	# Pick the highest-weighted counter tactic
	var chosen_tactic := ""
	var best_score := -1.0
	for tac in candidate_scores:
		if candidate_scores[tac] > best_score:
			best_score = candidate_scores[tac]
			chosen_tactic = tac

	last_tactic = chosen_tactic
	tactic_history.append(chosen_tactic)

	match chosen_tactic:
		"COUNTER_MOBILITY":
			return {
				"tactic": "COUNTER_MOBILITY",
				"banner_title": "DIRECTOR ADAPTATION // HIGH MOBILITY DETECTED",
				"banner_sub": "Dashers dropping ionization hazard lines • Shooters predicting evasion vectors",
				"enemy_speed_mult": 1.05,
				"enemy_telegraph_mult": 1.0,
				"extra_chasers": 0,
				"extra_dashers": 1,
				"extra_shooters": 0,
				"has_hazard_trail": true,
				"pincer_flanking": false,
				"shooter_lead": 0.75
			}

		"COUNTER_RANGED":
			return {
				"tactic": "COUNTER_RANGED",
				"banner_title": "DIRECTOR ADAPTATION // PERIMETER CAMPING DETECTED",
				"banner_sub": "Chasers evolving pincer flanking angles • Shooters leading long-range shots",
				"enemy_speed_mult": 1.16,
				"enemy_telegraph_mult": 1.0,
				"extra_chasers": 1,
				"extra_dashers": 0,
				"extra_shooters": 0,
				"has_hazard_trail": false,
				"pincer_flanking": true,
				"shooter_lead": 1.0
			}

		"COUNTER_TURRET":
			return {
				"tactic": "COUNTER_TURRET",
				"banner_title": "DIRECTOR ADAPTATION // STATIONARY FIRE DETECTED",
				"banner_sub": "Artillery barrage deployed • Pincer pursuers advancing to flush cover",
				"enemy_speed_mult": 1.0,
				"enemy_telegraph_mult": 0.90,
				"extra_chasers": 0,
				"extra_dashers": 0,
				"extra_shooters": 1,
				"has_hazard_trail": true,
				"pincer_flanking": true,
				"shooter_lead": 0.60
			}

		_:
			return _make_default_result("STANDARD DEPLOYMENT", "Tactical matrix aligned.")


func record_tactic_result(tactic: String, damage_taken: int) -> void:
	if tactic in tactic_weights:
		if damage_taken >= 3:
			# Unfair outcome: penalize selection weight
			tactic_weights[tactic] = maxf(0.35, tactic_weights[tactic] * 0.70)
		elif damage_taken <= 1:
			# Fair / cleanly countered: gradually restore weight
			tactic_weights[tactic] = minf(1.5, tactic_weights[tactic] * 1.15)


func _make_default_result(title: String, sub: String) -> Dictionary:
	return {
		"tactic": "DEFAULT",
		"banner_title": title,
		"banner_sub": sub,
		"enemy_speed_mult": 1.0,
		"enemy_telegraph_mult": 1.0,
		"extra_chasers": 0,
		"extra_dashers": 0,
		"extra_shooters": 0,
		"has_hazard_trail": false,
		"pincer_flanking": false,
		"shooter_lead": 0.0
	}
