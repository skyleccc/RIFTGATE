extends Node2D

@onready var level_root: Node = $LevelLayout
@onready var bgm_player: AudioStreamPlayer = $BackgroundMusic
@onready var debug_hud: CanvasLayer = $DebugHUD

var level_scene: PackedScene

var current_level: Node = null

func _ready() -> void:
	pass

func _process(delta: float) -> void:
	check_for_debug_input()

func check_for_debug_input() -> void:
	if Input.is_action_just_pressed("ShowDebugHUD"):
		debug_hud.visible = not debug_hud.visible
		print("DebugHUD is enabled.") if debug_hud.visible else print("DebugHUD is disabled.")
	
	
## Level Manager

func _load_level(level_number: int) -> void:
	if current_level:
		current_level.queue_free()
	var level_path = "res://levels/Level%d.tscn" % level_number
	var level_resource = ResourceLoader.load(level_path)
	if level_resource and level_resource is PackedScene:
		current_level = level_resource.instantiate()
		get_tree().current_scene.add_child(current_level)
		print("Loaded %s" % level_path)
	else:
		push_error("Failed to load level scene: %s" % level_path)
