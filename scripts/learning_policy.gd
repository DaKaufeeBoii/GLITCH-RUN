extends RefCounted
class_name LearningPolicy
## Contextual Bandit (LinUCB) Online Learning Policy for tactical adaptation.
## Evaluates normalized player behavior & combat context, selects counter-actions,
## and updates policy parameters via exact Sherman-Morrison matrix rank-1 updates.

const FEATURE_DIM := 6

# High-level director actions
const DIRECTOR_ACTIONS: Array[String] = [
	"COUNTER_MOBILITY",
	"COUNTER_RANGED",
	"COUNTER_TURRET",
	"BALANCED_ATTRITION",
	"STABILIZATION"
]

const ACTION_NAMES: Array[String] = [
	"COUNTER_MOBILITY",
	"COUNTER_RANGED",
	"COUNTER_TURRET",
	"BALANCED_ATTRITION",
	"STABILIZATION"
]

# Species-specific action vocabularies
const SPECIES_ACTIONS: Dictionary = {
	"CHASER": [
		"CONTACT_PURSUIT",
		"RAPID_PURSUIT",
		"FLANKING_PINCER",
		"CRIMSON_BLASTER"
	],
	"DASHER": [
		"DIRECT_LUNGE",
		"ION_HAZARD_TRAIL",
		"OVERCLOCKED_THRUSTERS",
		"REINFORCED_CHASSIS"
	],
	"SHOOTER": [
		"STANDARD_VOLLEY",
		"AGILE_STRAFE",
		"PREDICTIVE_OPTICS",
		"HEAVY_BEAM"
	]
}

var family_id: String = "DIRECTOR" # "DIRECTOR", "CHASER", "DASHER", "SHOOTER"
var action_names: Array[String] = []
var action_count: int = 5
var exploration_alpha: float = 0.25

# LinUCB Matrices and Vectors:
# inv_cov[a] is the d x d inverted covariance matrix A_a^-1
# b_vec[a] is the d-dimensional reward accumulator vector b_a
# theta[a] is the d-dimensional parameter estimate A_a^-1 * b_a
var inv_cov: Array = [] # Array of Array of Array[float] (action_count x FEATURE_DIM x FEATURE_DIM)
var b_vec: Array = [] # Array of Array[float] (action_count x FEATURE_DIM)
var theta: Array = [] # Array of Array[float] (action_count x FEATURE_DIM)
var action_counts: Array[int] = []

var last_selected_action := -1
var last_context_vector: Array[float] = []
var action_history: Array[int] = []


func _init(p_family_id: String = "DIRECTOR", p_alpha: float = 0.25) -> void:
	family_id = p_family_id
	exploration_alpha = p_alpha
	if SPECIES_ACTIONS.has(family_id):
		action_names = []
		for a_name in SPECIES_ACTIONS[family_id]:
			action_names.append(a_name)
	else:
		action_names = []
		for d_name in DIRECTOR_ACTIONS:
			action_names.append(d_name)
	action_count = action_names.size()
	reset()


func reset() -> void:
	inv_cov.clear()
	b_vec.clear()
	theta.clear()
	action_counts.clear()
	last_selected_action = -1
	last_context_vector.clear()
	action_history.clear()

	for a in range(action_count):
		action_counts.append(0)
		# Initialize A_a^-1 as identity matrix I_d (ridge parameter lambda = 1.0)
		var mat: Array = []
		for i in range(FEATURE_DIM):
			var row: Array[float] = []
			for j in range(FEATURE_DIM):
				row.append(1.0 if i == j else 0.0)
			mat.append(row)
		inv_cov.append(mat)

		# Initialize b_a as zeros
		var b: Array[float] = []
		var th: Array[float] = []
		for f in range(FEATURE_DIM):
			b.append(0.0)
			th.append(0.0)
		b_vec.append(b)
		theta.append(th)

	# Seed rational domain baseline priors so cold-start performs intelligibly
	_seed_domain_priors()


func _seed_domain_priors() -> void:
	# Features: [0: bias=1.0, 1: mobility, 2: ranged, 3: turret, 4: aggression, 5: chokepoint_ratio]
	if family_id == "DIRECTOR":
		# COUNTER_MOBILITY correlates with mobility
		b_vec[0][1] = 1.0
		# COUNTER_RANGED correlates with ranged
		b_vec[1][2] = 1.0
		# COUNTER_TURRET correlates with turret
		b_vec[2][3] = 1.0
		# BALANCED_ATTRITION has baseline bias
		b_vec[3][0] = 0.4
	elif family_id == "CHASER":
		# RAPID_PURSUIT correlates with kiting (ranged) and mobility
		b_vec[1][1] = 0.8
		b_vec[1][2] = 1.2
		# CRIMSON_BLASTER correlates strongly with kiting
		b_vec[3][2] = 1.5
	elif family_id == "DASHER":
		# ION_HAZARD_TRAIL correlates with mobility (dash evasion)
		b_vec[1][1] = 1.2
		# OVERCLOCKED_THRUSTERS correlates with mobility
		b_vec[2][1] = 1.4
	elif family_id == "SHOOTER":
		# AGILE_STRAFE correlates with aggression (player rushing)
		b_vec[1][4] = 1.0
		# PREDICTIVE_OPTICS correlates with mobility
		b_vec[2][1] = 1.2
		# HEAVY_BEAM correlates with turret camping
		b_vec[3][3] = 1.5

	# Update initial theta = inv_cov * b_vec
	for a in range(action_count):
		_recalculate_theta(a)


func extract_context(profile: Dictionary, room_chokepoint_ratio: float = 0.0) -> Array[float]:
	# Features: [0: bias=1.0, 1: mobility, 2: ranged, 3: turret, 4: aggression, 5: chokepoint_ratio]
	var vec: Array[float] = [
		1.0,
		clampf(float(profile.get("mobility", 0.5)), 0.0, 1.0),
		clampf(float(profile.get("ranged", 0.5)), 0.0, 1.0),
		clampf(float(profile.get("turret", 0.5)), 0.0, 1.0),
		clampf(float(profile.get("aggression", 0.5)), 0.0, 1.0),
		clampf(room_chokepoint_ratio, 0.0, 1.0)
	]
	return vec


func select_action(context: Array[float], current_hp: int = 5, max_hp: int = 5, allow_stabilization: bool = true) -> Dictionary:
	last_context_vector = context.duplicate()

	# Mercy stabilization override for high-level Director only
	if family_id == "DIRECTOR" and allow_stabilization:
		var hp_ratio := float(current_hp) / maxf(1.0, float(max_hp))
		if hp_ratio <= 0.35:
			var stab_idx := action_names.find("STABILIZATION")
			if stab_idx >= 0:
				last_selected_action = stab_idx
				action_history.append(stab_idx)
				return {
					"action_id": stab_idx,
					"action_name": "STABILIZATION",
					"confidence": 1.0,
					"reason": "Fairness mercy stabilization triggered (Player HP <= 35%)",
					"ucb_scores": [0.0, 0.0, 0.0, 0.0, 1.0]
				}

	var best_score := -9999.0
	var chosen_action := 0
	var ucb_scores: Array[float] = []
	for a in range(action_count):
		ucb_scores.append(0.0)

	var candidate_limit := action_count
	if family_id == "DIRECTOR":
		candidate_limit = action_count - 1 # Exclude automatic stabilization when player is healthy

	for a in range(candidate_limit):
		# 1. Expected reward = theta[a] . x
		var expected_reward := 0.0
		for f in range(FEATURE_DIM):
			expected_reward += theta[a][f] * context[f]

		# 2. UCB exploration bonus = alpha * sqrt(x^T * inv_cov[a] * x)
		var variance := 0.0
		for i in range(FEATURE_DIM):
			var row_sum := 0.0
			for j in range(FEATURE_DIM):
				row_sum += inv_cov[a][i][j] * context[j]
			variance += context[i] * row_sum

		var ucb_bonus := exploration_alpha * sqrt(maxf(0.001, variance))
		var total_score := expected_reward + ucb_bonus

		# Repetition penalty for consecutive identical action selection
		if not action_history.is_empty() and action_history[-1] == a:
			total_score -= 0.40

		ucb_scores[a] = total_score
		if total_score > best_score:
			best_score = total_score
			chosen_action = a

	last_selected_action = chosen_action
	action_history.append(chosen_action)

	var chosen_name: String = action_names[chosen_action]
	var reason_text: String = "LinUCB [%s] selected %s [Mob: %.2f, Rng: %.2f, Agg: %.2f, Sta: %.2f]" % [
		family_id,
		chosen_name,
		context[1],
		context[2],
		context[3],
		context[4]
	]

	return {
		"action_id": chosen_action,
		"action_name": chosen_name,
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
	## Multi-objective reward balancing challenge, tactical match, and fairness.
	var engagement_score := 0.0
	if combat_duration >= 8.0 and combat_duration <= 32.0:
		engagement_score = 1.0
	elif combat_duration < 8.0:
		engagement_score = combat_duration / 8.0
	else:
		engagement_score = maxf(0.0, 1.0 - (combat_duration - 32.0) / 25.0)

	# Tactical match score based on player profile
	var match_score := 0.0
	var act_name: String = action_names[selected_action] if selected_action < action_names.size() else ""
	var mob: float = float(player_profile.get("mobility", 0.5))
	var rng: float = float(player_profile.get("ranged", 0.5))
	var agg: float = float(player_profile.get("aggression", 0.5))
	var sta: float = float(player_profile.get("turret", 0.5))

	match act_name:
		"COUNTER_MOBILITY", "RAPID_PURSUIT", "OVERCLOCKED_THRUSTERS":
			match_score = mob * 0.5 + rng * 0.5
		"COUNTER_RANGED", "CRIMSON_BLASTER":
			match_score = rng
		"ION_HAZARD_TRAIL":
			match_score = mob
		"COUNTER_TURRET", "HEAVY_BEAM":
			match_score = sta
		"AGILE_STRAFE":
			match_score = agg
		"PREDICTIVE_OPTICS":
			match_score = mob * 0.6 + rng * 0.4
		"BALANCED_ATTRITION", "CONTACT_PURSUIT", "DIRECT_LUNGE", "STANDARD_VOLLEY":
			match_score = 0.50
		"STABILIZATION":
			match_score = 1.0 if player_damage_taken <= 1 else 0.2
		_:
			match_score = 0.50

	# Overkill penalty: taking >= 3 damage is an unfair encounter
	var overkill_penalty := 0.0
	if player_damage_taken >= 3:
		overkill_penalty = float(player_damage_taken - 2) * 1.5

	var total_reward: float = (engagement_score * 0.40) + (match_score * 0.60) - overkill_penalty
	return clampf(total_reward, -2.0, 2.0)


func update_policy(reward: float) -> void:
	if last_selected_action < 0 or last_context_vector.is_empty():
		return

	var a := last_selected_action
	action_counts[a] += 1
	var x := last_context_vector

	# Exact Sherman-Morrison rank-1 update of inv_cov[a]:
	# u = inv_cov[a] * x
	# denom = 1.0 + x^T * u
	# inv_cov[a] = inv_cov[a] - (u * u^T) / denom
	var u: Array[float] = []
	for i in range(FEATURE_DIM):
		var sum := 0.0
		for j in range(FEATURE_DIM):
			sum += inv_cov[a][i][j] * x[j]
		u.append(sum)

	var denom := 1.0
	for i in range(FEATURE_DIM):
		denom += x[i] * u[i]

	denom = maxf(0.001, denom)
	for i in range(FEATURE_DIM):
		for j in range(FEATURE_DIM):
			inv_cov[a][i][j] -= (u[i] * u[j]) / denom

	# Update reward vector b[a] = b[a] + r * x
	for f in range(FEATURE_DIM):
		b_vec[a][f] += reward * x[f]

	# Recompute parameter vector theta[a] = inv_cov[a] * b_vec[a]
	_recalculate_theta(a)


func _recalculate_theta(a: int) -> void:
	for i in range(FEATURE_DIM):
		var sum := 0.0
		for j in range(FEATURE_DIM):
			sum += inv_cov[a][i][j] * b_vec[a][j]
		theta[a][i] = sum


func export_weights() -> Dictionary:
	return {
		"version": 2,
		"family_id": family_id,
		"feature_dim": FEATURE_DIM,
		"action_count": action_count,
		"action_names": action_names.duplicate(),
		"theta": theta.duplicate(true),
		"inv_cov": inv_cov.duplicate(true),
		"b_vec": b_vec.duplicate(true),
		"action_counts": action_counts.duplicate()
	}


func load_weights(data: Dictionary) -> bool:
	if not data.has("theta"):
		return false

	var ver: int = int(data.get("version", 0))
	if ver != 1 and ver != 2:
		return false

	if int(data.get("feature_dim", 0)) != FEATURE_DIM:
		return false

	var loaded_theta: Array = data.theta
	for a in range(mini(action_count, loaded_theta.size())):
		for f in range(FEATURE_DIM):
			theta[a][f] = float(loaded_theta[a][f])

	if ver == 2 and data.has("inv_cov") and data.has("b_vec"):
		var loaded_inv: Array = data.inv_cov
		var loaded_b: Array = data.b_vec
		for a in range(mini(action_count, loaded_inv.size())):
			for i in range(FEATURE_DIM):
				for j in range(FEATURE_DIM):
					inv_cov[a][i][j] = float(loaded_inv[a][i][j])
				b_vec[a][i] = float(loaded_b[a][i])
	elif ver == 1 and data.has("cov_diag"):
		for a in range(mini(action_count, data.cov_diag.size())):
			for f in range(FEATURE_DIM):
				inv_cov[a][f][f] = float(data.cov_diag[a][f])

	if data.has("action_counts") and data.action_counts is Array:
		action_counts.clear()
		for c in data.action_counts:
			action_counts.append(int(c))

	return true


func load_from_json_file(file_path: String = "res://assets/data/learned_policy_weights.json") -> bool:
	if not FileAccess.file_exists(file_path):
		return false

	var file := FileAccess.open(file_path, FileAccess.READ)
	if not file:
		return false

	var json_str := file.get_as_text()
	file.close()

	var json := JSON.new()
	if json.parse(json_str) != OK:
		return false

	return load_weights(json.data)
