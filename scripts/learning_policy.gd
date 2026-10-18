extends RefCounted
class_name LearningPolicy
## Contextual Bandit (LinUCB) Online Learning Policy for tactical adaptation.
## Evaluates normalized player behavior & room context, recommends counter-actions,
## and updates policy parameters via an explicit multi-objective reward function.

const FEATURE_DIM := 6
const ACTION_COUNT := 5

# Action definitions
const ACTION_COUNTER_MOBILITY := 0
const ACTION_COUNTER_RANGED := 1
const ACTION_COUNTER_TURRET := 2
const ACTION_BALANCED_ATTRITION := 3
const ACTION_STABILIZATION := 4

const ACTION_NAMES: Array[String] = [
	"COUNTER_MOBILITY",
	"COUNTER_RANGED",
	"COUNTER_TURRET",
	"BALANCED_ATTRITION",
	"STABILIZATION"
]

# Exploration parameter (alpha for UCB confidence bound)
@export var exploration_alpha := 0.25

# Ridge regression parameters per action
# A[a] is an inverted covariance matrix (approximate diagonal/full)
var theta: Array = [] # Array of Array[float] (ACTION_COUNT x FEATURE_DIM)
var cov_diag: Array = [] # Diagonal variance tracker (ACTION_COUNT x FEATURE_DIM)
var action_counts: Array[int] = [0, 0, 0, 0, 0]

var last_selected_action := -1
var last_context_vector: Array[float] = []
var action_history: Array[int] = []


func _init() -> void:
	reset()


func reset() -> void:
	theta.clear()
	cov_diag.clear()
	action_counts = [0, 0, 0, 0, 0]
	last_selected_action = -1
	last_context_vector.clear()
	action_history.clear()

	# Initialize weight vectors with sensible prior baselines
	for a in range(ACTION_COUNT):
		var w: Array[float] = []
		var c: Array[float] = []
		for f in range(FEATURE_DIM):
			w.append(0.0)
			c.append(1.0) # Initial variance
		theta.append(w)
		cov_diag.append(c)

	# Seed prior domain weights so cold-start performs rationally:
	# Features: [bias=1.0, mobility, ranged, turret, aggression, chokepoint_ratio]
	# COUNTER_MOBILITY correlates positively with mobility
	theta[ACTION_COUNTER_MOBILITY][1] = 1.2
	# COUNTER_RANGED correlates positively with ranged
	theta[ACTION_COUNTER_RANGED][2] = 1.2
	# COUNTER_TURRET correlates positively with turret
	theta[ACTION_COUNTER_TURRET][3] = 1.2
	# BALANCED_ATTRITION has solid baseline bias
	theta[ACTION_BALANCED_ATTRITION][0] = 0.4
	# STABILIZATION correlates negatively with overall aggression, handled via mercy checks


func extract_context(profile: Dictionary, room_chokepoint_ratio: float = 0.0) -> Array[float]:
	var vec: Array[float] = [
		1.0, # Bias feature
		clampf(float(profile.get("mobility", 0.5)), 0.0, 1.0),
		clampf(float(profile.get("ranged", 0.5)), 0.0, 1.0),
		clampf(float(profile.get("turret", 0.5)), 0.0, 1.0),
		clampf(float(profile.get("aggression", 0.5)), 0.0, 1.0),
		clampf(room_chokepoint_ratio, 0.0, 1.0)
	]
	return vec


func select_action(context: Array[float], current_hp: int, max_hp: int, allow_stabilization: bool = true) -> Dictionary:
	last_context_vector = context.duplicate()

	# Strict Fairness / Mercy Override: If player is critical, force STABILIZATION
	var hp_ratio := float(current_hp) / maxf(1.0, float(max_hp))
	if allow_stabilization and hp_ratio <= 0.35:
		last_selected_action = ACTION_STABILIZATION
		action_history.append(ACTION_STABILIZATION)
		return {
			"action_id": ACTION_STABILIZATION,
			"action_name": ACTION_NAMES[ACTION_STABILIZATION],
			"confidence": 1.0,
			"reason": "Fairness mercy stabilization triggered (Player HP <= 35%)",
			"ucb_scores": [0.0, 0.0, 0.0, 0.0, 1.0]
		}

	# Compute LinUCB score for each candidate action (excluding STABILIZATION when healthy)
	var best_score := -9999.0
	var chosen_action := ACTION_BALANCED_ATTRITION
	var ucb_scores: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0]

	for a in range(ACTION_COUNT - 1): # Exclude automatic stabilization
		# Dot product theta[a] * context
		var expected_reward := 0.0
		var variance_term := 0.0
		for f in range(FEATURE_DIM):
			expected_reward += theta[a][f] * context[f]
			variance_term += cov_diag[a][f] * (context[f] * context[f])

		# UCB bonus = alpha * sqrt(variance)
		var ucb_bonus := exploration_alpha * sqrt(maxf(0.01, variance_term))
		var total_score := expected_reward + ucb_bonus

		# Repetition penalty: reduce score if selected in immediate previous encounter
		if not action_history.is_empty() and action_history[-1] == a:
			total_score -= 0.65

		ucb_scores[a] = total_score
		if total_score > best_score:
			best_score = total_score
			chosen_action = a

	last_selected_action = chosen_action
	action_history.append(chosen_action)

	var reason_text: String = "LinUCB policy selected %s based on player context [Mob: %.2f, Rng: %.2f, Tur: %.2f]" % [
		ACTION_NAMES[chosen_action],
		context[1],
		context[2],
		context[3]
	]

	return {
		"action_id": chosen_action,
		"action_name": ACTION_NAMES[chosen_action],
		"confidence": clampf(best_score, 0.0, 1.0),
		"reason": reason_text,
		"ucb_scores": ucb_scores
	}


func compute_reward(
	player_damage_taken: int,
	combat_duration: float,
	player_profile: Dictionary,
	selected_action: int
) -> float:
	## Explicit Multi-Objective Reward Function:
	## 1. Challenge & Engagement: Reward encounters that last between 10s and 35s.
	## 2. Adaptation Precision: Reward matching the player's highest behavior trait.
	## 3. Strict Fairness Penalty: Penalize excessive player damage (>2 HP lost).
	## 4. Repetition Penalty: Penalize identical consecutive action selections.

	var engagement_score := 0.0
	if combat_duration >= 8.0 and combat_duration <= 35.0:
		engagement_score = 1.0
	elif combat_duration < 8.0:
		engagement_score = combat_duration / 8.0
	else:
		engagement_score = maxf(0.0, 1.0 - (combat_duration - 35.0) / 30.0)

	# Tactical match score
	var match_score := 0.0
	match selected_action:
		ACTION_COUNTER_MOBILITY:
			match_score = clampf(float(player_profile.get("mobility", 0.5)), 0.0, 1.0)
		ACTION_COUNTER_RANGED:
			match_score = clampf(float(player_profile.get("ranged", 0.5)), 0.0, 1.0)
		ACTION_COUNTER_TURRET:
			match_score = clampf(float(player_profile.get("turret", 0.5)), 0.0, 1.0)
		ACTION_BALANCED_ATTRITION:
			match_score = 0.60
		ACTION_STABILIZATION:
			match_score = 1.0 if player_damage_taken <= 1 else 0.3

	# Overkill penalty: taking >= 3 damage is an unfair encounter
	var overkill_penalty := 0.0
	if player_damage_taken >= 3:
		overkill_penalty = float(player_damage_taken - 2) * 1.5

	# Calculate final composite reward
	var total_reward: float = (engagement_score * 0.40) + (match_score * 0.60) - overkill_penalty
	return clampf(total_reward, -2.0, 2.0)


func update_policy(reward: float) -> void:
	if last_selected_action < 0 or last_context_vector.is_empty():
		return

	var a := last_selected_action
	action_counts[a] += 1
	var learning_rate: float = 1.0 / float(action_counts[a] + 1)
	learning_rate = clampf(learning_rate, 0.05, 0.35)

	# Update feature weights theta[a] via recursive gradient step
	for f in range(FEATURE_DIM):
		var feat: float = last_context_vector[f]
		# Predict error
		var pred: float = float(theta[a][f]) * feat
		var err: float = reward - pred
		theta[a][f] += learning_rate * err * feat
		# Decrease parameter uncertainty
		cov_diag[a][f] = maxf(0.05, cov_diag[a][f] * 0.95)


func export_weights() -> Dictionary:
	return {
		"version": 1,
		"feature_dim": FEATURE_DIM,
		"action_count": ACTION_COUNT,
		"theta": theta.duplicate(true),
		"cov_diag": cov_diag.duplicate(true),
		"action_counts": action_counts.duplicate()
	}


func load_weights(d: Dictionary) -> bool:
	if int(d.get("version", 0)) != 1:
		return false
	var loaded_theta: Array = d.get("theta", [])
	if loaded_theta.size() == ACTION_COUNT:
		theta = loaded_theta.duplicate(true)

	var loaded_cov: Array = d.get("cov_diag", [])
	if loaded_cov.size() == ACTION_COUNT:
		cov_diag = loaded_cov.duplicate(true)
	else:
		# Fallback to sensible initial variance if missing from weights dict
		cov_diag.clear()
		for a in range(ACTION_COUNT):
			var c: Array[float] = []
			for f in range(FEATURE_DIM):
				c.append(0.5)
			cov_diag.append(c)

	var loaded_counts: Array = d.get("action_counts", [])
	if loaded_counts.size() == ACTION_COUNT:
		action_counts.assign(loaded_counts)
	return true


func load_from_json_file(file_path: String = "res://assets/data/learned_policy_weights.json") -> bool:
	if not FileAccess.file_exists(file_path):
		return false
	var file := FileAccess.open(file_path, FileAccess.READ)
	if not file:
		return false
	var json_str := file.get_as_text()
	file.close()

	var test_json := JSON.new()
	var err := test_json.parse(json_str)
	if err != OK or not (test_json.data is Dictionary):
		return false
	return load_weights(test_json.data)
