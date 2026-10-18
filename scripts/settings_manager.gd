extends Node
## Central manager for player settings: audio bus volumes, screen shake,
## haptics, and input preferences. Persists to user://settings.json.

signal settings_changed

const SETTINGS_FILE := "user://settings.json"

var master_volume: float = 1.0 # 0.0 to 1.0
var music_volume: float = 0.75 # 0.0 to 1.0
var sfx_volume: float = 0.9 # 0.0 to 1.0
var screen_shake_enabled: bool = true
var screen_shake_intensity: float = 1.0 # 0.0 to 1.5
var haptics_enabled: bool = true


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_audio_buses()
	load_settings()
	apply_all()


func _setup_audio_buses() -> void:
	# Ensure "Music" and "SFX" buses exist in AudioServer
	if AudioServer.get_bus_index("Music") == -1:
		AudioServer.add_bus()
		var idx := AudioServer.get_bus_count() - 1
		AudioServer.set_bus_name(idx, "Music")
		AudioServer.set_bus_send(idx, "Master")

	if AudioServer.get_bus_index("SFX") == -1:
		AudioServer.add_bus()
		var idx := AudioServer.get_bus_count() - 1
		AudioServer.set_bus_name(idx, "SFX")
		AudioServer.set_bus_send(idx, "Master")


func load_settings() -> void:
	if not FileAccess.file_exists(SETTINGS_FILE):
		return
	var file := FileAccess.open(SETTINGS_FILE, FileAccess.READ)
	if not file:
		return
	var json_str := file.get_as_text()
	file.close()

	var json := JSON.new()
	var err := json.parse(json_str)
	if err != OK or not (json.data is Dictionary):
		return
	var data: Dictionary = json.data

	master_volume = clampf(float(data.get("master_volume", 1.0)), 0.0, 1.0)
	music_volume = clampf(float(data.get("music_volume", 0.75)), 0.0, 1.0)
	sfx_volume = clampf(float(data.get("sfx_volume", 0.9)), 0.0, 1.0)
	screen_shake_enabled = bool(data.get("screen_shake_enabled", true))
	screen_shake_intensity = clampf(float(data.get("screen_shake_intensity", 1.0)), 0.0, 1.5)
	haptics_enabled = bool(data.get("haptics_enabled", true))


func save_settings() -> void:
	var file := FileAccess.open(SETTINGS_FILE, FileAccess.WRITE)
	if not file:
		return
	var d := {
		"master_volume": master_volume,
		"music_volume": music_volume,
		"sfx_volume": sfx_volume,
		"screen_shake_enabled": screen_shake_enabled,
		"screen_shake_intensity": screen_shake_intensity,
		"haptics_enabled": haptics_enabled
	}
	file.store_string(JSON.stringify(d, "\t"))
	file.close()


func apply_all() -> void:
	set_bus_volume("Master", master_volume)
	set_bus_volume("Music", music_volume)
	set_bus_volume("SFX", sfx_volume)
	settings_changed.emit()


func set_bus_volume(bus_name: String, linear_vol: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx == -1:
		return
	var clamped := clampf(linear_vol, 0.0, 1.0)
	var db := linear_to_db(clamped)
	if clamped <= 0.001:
		db = -80.0
	AudioServer.set_bus_volume_db(idx, db)
	AudioServer.set_bus_mute(idx, clamped <= 0.001)


func trigger_haptic(duration_ms: int = 40) -> void:
	if not haptics_enabled:
		return
	if OS.has_feature("android") or OS.has_feature("mobile"):
		Input.vibrate_handheld(duration_ms)
