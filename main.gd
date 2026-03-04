extends Node2D

@onready var bgm_player: AudioStreamPlayer = $BackgroundMusic
@onready var debug_hud: CanvasLayer = $DebugHUD

func _ready() -> void:
	pass

func _process(delta: float) -> void:
	check_for_debug_input()

func check_for_debug_input() -> void:
	if Input.is_action_just_pressed("ShowDebugHUD"):
		debug_hud.visible = not debug_hud.visible
		print("DebugHUD is enabled.") if debug_hud.visible else print("DebugHUD is disabled.")
	
	
		
