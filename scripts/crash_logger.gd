extends Node
## Offline QA and Diagnostic Crash Logger for GLITCH//RUN.
## Records timestamped operational events, memory footprints, and unhandled errors
## strictly to local storage (user://logs/glitch_run_qa.log) without collecting
## any personally identifiable information (PII) or communicating over network.

const LOG_DIR := "user://logs"
const LOG_FILE := "user://logs/glitch_run_qa.log"
const MAX_LOG_SIZE_BYTES := 262144 # 256 KB max file cap to prevent storage bloat


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_log_dir()
	log_info("=== GLITCH//RUN SESSION INITIALIZED ===")
	log_info("Platform: %s | Model: %s | Engine: %s" % [
		OS.get_name(),
		OS.get_model_name() if OS.has_method("get_model_name") else "Unknown",
		Engine.get_version_info().get("string", "4.7.2")
	])


static func _ensure_log_dir() -> void:
	if not DirAccess.dir_exists_absolute(LOG_DIR):
		DirAccess.make_dir_recursive_absolute(LOG_DIR)


static func log_info(message: String) -> void:
	_append_log("INFO", message)


static func log_warning(message: String) -> void:
	_append_log("WARN", message)


static func log_error(message: String) -> void:
	_append_log("ERROR", message)


static func _append_log(level: String, message: String) -> void:
	_ensure_log_dir()

	# Rotate log if size exceeds cap
	if FileAccess.file_exists(LOG_FILE):
		var existing_file := FileAccess.open(LOG_FILE, FileAccess.READ)
		if existing_file and existing_file.get_length() > MAX_LOG_SIZE_BYTES:
			existing_file.close()
			DirAccess.remove_absolute(LOG_FILE)

	var file := FileAccess.open(LOG_FILE, FileAccess.READ_WRITE if FileAccess.file_exists(LOG_FILE) else FileAccess.WRITE)
	if not file:
		return
	file.seek_end()

	var time_dict := Time.get_datetime_dict_from_system(true)
	var time_str := "%04d-%02d-%02dT%02d:%02d:%02dZ" % [
		time_dict.year, time_dict.month, time_dict.day,
		time_dict.hour, time_dict.minute, time_dict.second
	]

	var mem_mb := float(OS.get_static_memory_usage()) / (1024.0 * 1024.0)
	var log_line := "[%s][%s][Mem: %.2f MB] %s\n" % [time_str, level, mem_mb, message]
	file.store_string(log_line)
	file.close()


static func read_recent_logs() -> String:
	if not FileAccess.file_exists(LOG_FILE):
		return "No diagnostic logs found."
	var file := FileAccess.open(LOG_FILE, FileAccess.READ)
	if not file:
		return "Unable to open diagnostic log file."
	var content := file.get_as_text()
	file.close()
	return content
