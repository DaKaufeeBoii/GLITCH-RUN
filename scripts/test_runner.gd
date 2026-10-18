extends SceneTree
## Headless CLI Test Runner for GLITCH//RUN test suite.
## Prepares user:// before persistence scenarios run.

func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	var user_root := ProjectSettings.globalize_path("user://")
	DirAccess.make_dir_recursive_absolute(user_root)
	DirAccess.make_dir_recursive_absolute(user_root.path_join("logs"))
	var test_script = load("res://scripts/test_director.gd")
	if test_script == null:
		push_error("Unable to load deterministic test suite.")
		quit(1)
		return
	var success: bool = test_script.run_all_tests()
	quit(0 if success else 1)
