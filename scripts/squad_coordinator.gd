extends RefCounted
class_name SquadCoordinator
## Coordinates hostile squad aggression, preventing simultaneous unavoidable attacks
## by managing a shared high-threat attack budget and enforcing telegraph staggering.

var max_concurrent_threat_tokens: int = 1
var min_stagger_cooldown: float = 0.45
var active_attackers: Array[Node2D] = []
var last_attack_time: float = -99.0


func _init(max_tokens: int = 1, stagger: float = 0.45) -> void:
	max_concurrent_threat_tokens = max_tokens
	min_stagger_cooldown = stagger


func reset() -> void:
	active_attackers.clear()
	last_attack_time = -99.0


func configure_for_depth(depth: int, player_hp: int) -> void:
	## Scales threat budget with depth, applying fairness stabilization when player HP is low.
	if player_hp <= 2:
		# Health-based fairness stabilization: strictly cap to 1 token and lengthen stagger window
		max_concurrent_threat_tokens = 1
		min_stagger_cooldown = 0.65
	elif depth >= 8:
		# Deep run scaling: allow 2 simultaneous tokens with tight stagger
		max_concurrent_threat_tokens = 2
		min_stagger_cooldown = 0.35
	else:
		max_concurrent_threat_tokens = 1
		min_stagger_cooldown = 0.45


func request_attack_token(enemy: Node2D, current_time: float) -> bool:
	## Returns true if the enemy is granted permission to start a high-threat telegraph.
	_clean_inactive()

	if enemy in active_attackers:
		return true

	if active_attackers.size() >= max_concurrent_threat_tokens:
		return false

	if current_time - last_attack_time < min_stagger_cooldown:
		return false

	active_attackers.append(enemy)
	last_attack_time = current_time
	return true


func release_attack_token(enemy: Node2D) -> void:
	## Frees attack token upon attack execution or cancellation.
	active_attackers.erase(enemy)


func is_attacker_active(enemy: Node2D) -> bool:
	return enemy in active_attackers


func _clean_inactive() -> void:
	var valid: Array[Node2D] = []
	for a in active_attackers:
		if is_instance_valid(a) and not a.is_queued_for_deletion():
			valid.append(a)
	active_attackers = valid
