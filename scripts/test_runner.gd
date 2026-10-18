extends SceneTree
## Headless CLI Test Runner for GLITCH//RUN test suite.

func _init() -> void:
	var success: bool = DirectorTests.run_all_tests()
	quit(0 if success else 1)
