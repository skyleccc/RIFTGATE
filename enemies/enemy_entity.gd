class_name Enemy
extends CharacterBody2D

# ── Shared Stats ───────────────────────────────────────────────────────────────
@export_group("Stats")
@export var max_hp: int = 50
@export var move_speed: float = 60.0
@export var chase_speed: float = 120.0

@export_group("Timers")
@export var deaggro_time: float = 2.0
@export var roam_idle_min: float = 1.0
@export var roam_idle_max: float = 3.0
@export var roam_walk_min: float = 1.0
@export var roam_walk_max: float = 3.0

@export_group("Line of Sight")
@export var los_range: float = 200.0
@export var los_rear: float = 60.0

@export_group("Edge Detection")
@export var edge_ray_horizontal: float = 20.0
@export var edge_ray_vertical: float = 30.0

@export_group("Wall Detection")
@export var wall_ray_length: float = 15.0

# ── Shared Internal State ──────────────────────────────────────────────────────
var current_hp: int
var target: Node2D = null
var facing: float = 1.0

var _roam_timer: float = 0.0
var _idle_timer: float = 0.0
var _roam_direction: float = 0.0
var _deaggro_timer: float = 0.0
var _player_in_deaggro: bool = false
var _has_los: bool = false

var _edge_ray_left: RayCast2D
var _edge_ray_right: RayCast2D
var _los_ray_left: RayCast2D
var _los_ray_right: RayCast2D
var _wall_ray_left: RayCast2D
var _wall_ray_right: RayCast2D

func _ready() -> void:
	current_hp = max_hp
	add_to_group("enemies")
	_setup_edge_detection()
	_setup_los_raycasts()
	_setup_wall_detection()

# ── Shared Methods ─────────────────────────────────────────────────────────────

func _valid_target() -> bool:
	return target != null and is_instance_valid(target)
    
func _update_facing(dir: float) -> void:
	if dir == 0.0:
		return
	facing = dir

func _is_at_edge(direction: float) -> bool:
	if not is_on_floor():
		return false
	if direction < 0.0:
		return _edge_ray_left != null and not _edge_ray_left.is_colliding()
	elif direction > 0.0:
		return _edge_ray_right != null and not _edge_ray_right.is_colliding()
	return false

func _is_wall_ahead(direction: float) -> bool:
	if direction < 0.0:
		return _wall_ray_left != null and _wall_ray_left.is_colliding()
	elif direction > 0.0:
		return _wall_ray_right != null and _wall_ray_right.is_colliding()
	return false

func _update_los() -> void:
	if not is_instance_valid(self):
		return
	_has_los = false
	for ray in [_los_ray_left, _los_ray_right]:
		if ray.is_colliding():
			var collider = ray.get_collider()
			if collider and collider.has_method("take_damage"):
				_has_los = true
				if target == null or target != collider:
					target = collider
				return

func _notify_aggro() -> void:
	if _valid_target() and target.has_method("on_enemy_aggro"):
		target.on_enemy_aggro()

func _notify_deaggro() -> void:
	if _valid_target() and target.has_method("on_enemy_deaggro"):
		target.on_enemy_deaggro()

func _setup_edge_detection() -> void:
	_edge_ray_left = RayCast2D.new()
	_edge_ray_left.target_position = Vector2(-edge_ray_horizontal, edge_ray_vertical)
	_edge_ray_left.collision_mask = 2
	_edge_ray_left.enabled = true
	add_child(_edge_ray_left)

	_edge_ray_right = RayCast2D.new()
	_edge_ray_right.target_position = Vector2(edge_ray_horizontal, edge_ray_vertical)
	_edge_ray_right.collision_mask = 2
	_edge_ray_right.enabled = true
	add_child(_edge_ray_right)

func _setup_los_raycasts() -> void:
	_los_ray_left = RayCast2D.new()
	_los_ray_left.target_position = Vector2(-los_range, 0.0)
	_los_ray_left.collision_mask = 3
	_los_ray_left.enabled = true
	add_child(_los_ray_left)

	_los_ray_right = RayCast2D.new()
	_los_ray_right.target_position = Vector2(los_range, 0.0)
	_los_ray_right.collision_mask = 3
	_los_ray_right.enabled = true
	add_child(_los_ray_right)

func _setup_wall_detection() -> void:
	_wall_ray_left = RayCast2D.new()
	_wall_ray_left.target_position = Vector2(-wall_ray_length, 0.0)
	_wall_ray_left.collision_mask = 10
	_wall_ray_left.enabled = true
	add_child(_wall_ray_left)

	_wall_ray_right = RayCast2D.new()
	_wall_ray_right.target_position = Vector2(wall_ray_length, 0.0)
	_wall_ray_right.collision_mask = 10
	_wall_ray_right.enabled = true
	add_child(_wall_ray_right)