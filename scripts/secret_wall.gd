extends StaticBody2D
class_name SecretWall
## Destructible secret wall for hidden rooms in GLITCH//RUN.
## Fractures when hit by player projectiles, dash impact, or nearby explosions.

var game_ref: Node2D = null
var room_index: int = -1

func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	add_to_group("obstacles")
	add_to_group("secret_walls")

func take_damage(_amount: int = 1, _source: String = "") -> void:
	if is_instance_valid(game_ref) and game_ref.has_method("reveal_secret_room"):
		game_ref.reveal_secret_room(room_index)
