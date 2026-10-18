extends RefCounted
class_name BossDefinition
## Authored data definition for GLITCH//RUN boss encounters.
## Defines base stats, attack profile, visual accents, eligibility, and allowed mutation tiers with trade-offs.

var boss_id: String = ""
var display_name: String = ""
var subtitle: String = ""
var scene_path: String = ""
var min_sector: int = 1
var base_health: int = 35
var base_speed: float = 55.0
var accent_color: Color = Color("f43f5e")
var allowed_mutations: Array[Dictionary] = []


func _init(
	p_id: String = "",
	p_name: String = "",
	p_subtitle: String = "",
	p_scene: String = "",
	p_min_sector: int = 1,
	p_health: int = 35,
	p_speed: float = 55.0,
	p_color: Color = Color("f43f5e"),
	p_mutations: Array[Dictionary] = []
) -> void:
	boss_id = p_id
	display_name = p_name
	subtitle = p_subtitle
	scene_path = p_scene
	min_sector = p_min_sector
	base_health = p_health
	base_speed = p_speed
	accent_color = p_color
	allowed_mutations = p_mutations


func to_dict() -> Dictionary:
	return {
		"boss_id": boss_id,
		"display_name": display_name,
		"subtitle": subtitle,
		"scene_path": scene_path,
		"min_sector": min_sector,
		"base_health": base_health,
		"base_speed": base_speed,
		"accent_color": accent_color.to_html()
	}
