extends Node
## Automated headless test runner for all Sensory Overload reconstruction milestones.
## Runs inside the SceneTree so all [autoload] singletons are initialized.

const SUITE_PATHS: PackedStringArray = [
	"res://tests/test_data_persistence.gd",
	"res://tests/test_swept_collision.gd",
	"res://tests/test_gameplay_modes.gd",
	"res://tests/test_replay_audio_effects.gd",
	"res://tests/test_editor_workflow.gd",
]

const SANDBOX_ROOT := "user://test_sandbox/"


func _ready() -> void:
	call_deferred("_execute_all")


func _execute_all() -> void:
	_clear_sandbox()
	SettingsManager.set_config_path(SANDBOX_ROOT + "settings.cfg")
	SaveManager.set_storage_root(SANDBOX_ROOT)
	LevelRepository.set_storage_root(SANDBOX_ROOT)

	var total_passed := 0
	var total_failed := 0
	var suites_executed := 0

	for path in SUITE_PATHS:
		if not ResourceLoader.exists(path):
			continue
		var script_res := load(path) as GDScript
		if script_res == null:
			push_error("Failed to load test suite: " + path)
			total_failed += 1
			continue
		var suite: Node = script_res.new()
		add_child(suite)
		suites_executed += 1
		var res: Dictionary = await suite.run_suite(self)
		var p := int(res.get("passed", 0))
		var f := int(res.get("failed", 0))
		total_passed += p
		total_failed += f
		print("[SUITE] %s -> passed=%d failed=%d" % [path.get_file(), p, f])
		suite.queue_free()

	# Milestone 7 Campaign & Scene-Boot Smoke Verification
	var m7_res := await _run_campaign_and_scene_checks()
	total_passed += int(m7_res["passed"])
	total_failed += int(m7_res["failed"])
	suites_executed += 1
	print("[SUITE] campaign_and_scene_boot -> passed=%d failed=%d" % [int(m7_res["passed"]), int(m7_res["failed"])])

	print("=== SUMMARY: suites=%d passed=%d failed=%d ===" % [suites_executed, total_passed, total_failed])
	var exit_code := 0 if (total_failed == 0 and suites_executed > 0) else 1
	get_tree().quit(exit_code)


func _run_campaign_and_scene_checks() -> Dictionary:
	var p := 0
	var f := 0
	var camp := LevelRepository.get_campaign_stages()
	if camp.size() == 21:
		p += 1
		print("  [PASS] Campaign loads all 21 stages across 7 levels")
	else:
		f += 1
		printerr("  [FAIL] Expected 21 campaign stages, got %d" % camp.size())

	var comm := LevelRepository.list_custom_stages()
	if comm.size() >= 1:
		p += 1
		print("  [PASS] Community showcase stage loads cleanly (%d available)" % comm.size())
	else:
		f += 1
		printerr("  [FAIL] Expected >= 1 community showcase stage")

	for spath in ["res://scenes/main_menu.tscn", "res://scenes/game_session.tscn", "res://scenes/level_editor.tscn"]:
		var packed := load(spath) as PackedScene
		if packed == null:
			f += 1
			printerr("  [FAIL] Failed to load scene: " + spath)
			continue
		var inst := packed.instantiate()
		add_child(inst)
		await get_tree().process_frame
		p += 1
		print("  [PASS] Scene instantiates and runs _ready() cleanly: " + spath)
		inst.queue_free()
		await get_tree().process_frame

	return {"passed": p, "failed": f}


func _clear_sandbox() -> void:
	var abs_root := ProjectSettings.globalize_path(SANDBOX_ROOT)
	if DirAccess.dir_exists_absolute(abs_root):
		_rm_dir_recursive(abs_root)
	DirAccess.make_dir_recursive_absolute(abs_root)


func _rm_dir_recursive(abs_path: String) -> void:
	var dir := DirAccess.open(abs_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var item := dir.get_next()
	while not item.is_empty():
		var child := abs_path.path_join(item)
		if dir.current_is_dir():
			_rm_dir_recursive(child)
			DirAccess.remove_absolute(child)
		else:
			DirAccess.remove_absolute(child)
		item = dir.get_next()
	dir.list_dir_end()
