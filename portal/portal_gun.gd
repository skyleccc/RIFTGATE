extends Node2D

## Portal gun that fires portals onto surfaces using raycasts.
## Left-click places the blue portal, right-click places the orange portal.
## Press R to clear both portals.
##
## Portals can only be placed on static collision surfaces (walls, floors, ceilings).
## A laser sight line shows where the portal will land.

@export var blue_portal_scene: PackedScene
@export var orange_portal_scene: PackedScene

@onready var sprite: Sprite2D = $Sprite2D
@onready var sound_player: AudioStreamPlayer = $AudioStreamPlayer

# Sound list
const SHOOT_BLUE_SOUND: AudioStream = preload("res://portal/sounds/portalgun_shoot_blue1.wav")
const SHOOT_ORANGE_SOUND: AudioStream = preload("res://portal/sounds/portalgun_shoot_red1.wav")
const SHOOT_FAIL_SOUND: AudioStream = preload("res://portal/sounds/portal_invalid_surface3.wav")
const RESET_PORTAL_SOUND: AudioStream = preload("res://portal/sounds/portal_close1.wav")

## How far the raycast reaches
const RAY_LENGTH := 2000.0
## Collision mask for portal-able surfaces (layer 2 = Walls, layer 6 = PortalSurfaces)
const SURFACE_MASK := 34
## Half-height of the PortalWallSurface collision shape (36 / 2)
const PORTAL_HALF_HEIGHT := 18.0
## Number of probe rays along the portal height to validate wall coverage
const SURFACE_CHECK_STEPS := 4

var active_blue_portal: Node2D = null
var active_orange_portal: Node2D = null

## Cached aim result for drawing the laser sight
var _aim_hit_pos: Vector2 = Vector2.ZERO
var _aim_hit_normal: Vector2 = Vector2.ZERO
var _aim_valid := false

func _process(_delta: float) -> void:
	_update_gun_direction()

	# Update aim data for the laser sight
	_update_aim()

	# Fire portals
	if Input.is_action_just_pressed("BluePortal"):
		_play_sound(SHOOT_BLUE_SOUND) if _spawn_portal("blue") else _play_sound(SHOOT_FAIL_SOUND)

	elif Input.is_action_just_pressed("OrangePortal"):
		_play_sound(SHOOT_ORANGE_SOUND) if _spawn_portal("orange") else _play_sound(SHOOT_FAIL_SOUND)

	# Reset both portals
	if Input.is_action_just_pressed("ResetPortals"):
		_clear_portals()
		_play_sound(RESET_PORTAL_SOUND)

func _update_gun_direction() -> void:
	var mouse_pos: Vector2 = get_global_mouse_position()
	look_at(mouse_pos)
	rotation_degrees = wrap(rotation_degrees, 0, 360) # Keep rotation between -180 and 180 for easier debugging
	if rotation_degrees > 90 and rotation_degrees < 270:
		scale.y = -1.0
	else:
		scale.y = 1.0


func _update_aim() -> void:
	var result := _raycast_to_surface()
	if result and _is_surface_valid_for_portal(result.position, result.normal):
		_aim_hit_pos = result.position
		_aim_hit_normal = result.normal
		_aim_valid = true
	else:
		_aim_hit_pos = global_position + global_transform.x * RAY_LENGTH
		_aim_valid = false

## Plays the given audio stream. Note: using a single AudioStreamPlayer means
## a new sound will cut off any currently playing sound.
func _play_sound(stream: AudioStream) -> void:
	if sound_player and is_instance_valid(sound_player) and stream:
		sound_player.stream = stream
		sound_player.play()

func _spawn_portal(type: String) -> bool:
	var result := _raycast_to_surface()
	if not result:
		return false  # No valid surface hit

	# Verify the wall covers the full portal height
	if not _is_surface_valid_for_portal(result.position, result.normal):
		return false

	# Create the portal instance
	var new_portal: Node2D
	if type == "blue":
		if active_blue_portal:
			active_blue_portal.queue_free()
		new_portal = blue_portal_scene.instantiate()
		active_blue_portal = new_portal
	else:
		if active_orange_portal:
			active_orange_portal.queue_free()
		new_portal = orange_portal_scene.instantiate()
		active_orange_portal = new_portal

	# Add to the scene tree
	get_tree().current_scene.add_child(new_portal)

	# Position and orient: local X axis = surface normal (outward)
	new_portal.global_position = result.position
	new_portal.global_rotation = result.normal.angle()
	new_portal.add_to_group("portals")

	# Link portals together if both exist
	_link_portals()
	return true

func _raycast_to_surface() -> Dictionary:
	var space_state := get_world_2d().direct_space_state
	var from := global_position
	var to := from + global_transform.x * RAY_LENGTH
	var query := PhysicsRayQueryParameters2D.create(from, to, SURFACE_MASK)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	return space_state.intersect_ray(query)

func _link_portals() -> void:
	if active_blue_portal and active_orange_portal:
		active_blue_portal.linked_portal = active_orange_portal
		active_orange_portal.linked_portal = active_blue_portal
	elif active_blue_portal:
		active_blue_portal.linked_portal = null
	elif active_orange_portal:
		active_orange_portal.linked_portal = null

## Checks whether the wall surface at hit_pos fully covers the portal height.
## Casts probe rays at evenly-spaced points along the portal's span.
## Returns false if any probe misses, meaning the wall has a gap or edge.
func _is_surface_valid_for_portal(hit_pos: Vector2, hit_normal: Vector2) -> bool:
	# Tangent runs along the wall surface (perpendicular to normal)
	var tangent := Vector2(-hit_normal.y, hit_normal.x)
	var probe_start := 5.0   # start ray slightly in front of the wall
	var probe_depth := 15.0  # cast into the wall

	var space_state := get_world_2d().direct_space_state

	# Check evenly-spaced points from -PORTAL_HALF_HEIGHT to +PORTAL_HALF_HEIGHT
	for i in range(SURFACE_CHECK_STEPS + 1):
		var t: float = -PORTAL_HALF_HEIGHT + (2.0 * PORTAL_HALF_HEIGHT) * i / SURFACE_CHECK_STEPS
		var origin := hit_pos + tangent * t + hit_normal * probe_start
		var target := origin - hit_normal * probe_depth
		var query := PhysicsRayQueryParameters2D.create(origin, target, SURFACE_MASK)
		query.collide_with_areas = false
		query.collide_with_bodies = true
		var probe_result := space_state.intersect_ray(query)
		if not probe_result:
			return false
	return true

func _clear_portals() -> void:
	if active_blue_portal:
		active_blue_portal.queue_free()
		active_blue_portal = null
	if active_orange_portal:
		active_orange_portal.queue_free()
		active_orange_portal = null
