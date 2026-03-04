extends PortalEntity

## Striker bullet — travels in a straight line and can teleport through portals.
## Extends PortalEntity so portals detect it as a physics body.

@export var speed: float = 200.0
@export var lifetime: float = 2.0
@export var damage: int = 10
@export var allow_friendly_fire: bool = false  ## If true, bullet can damage enemies too

var hit_scene: PackedScene = preload("res://enemies/StrikerBulletHit.tscn")
var direction: float = 1.0  # -1 = left, 1 = right
var _time_alive: float = 0.0

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D


func _ready() -> void:
	add_to_group("striker_bullets")
	animated_sprite.play("default")


func initialize() -> void:
	velocity = Vector2(direction * speed, 0)
	animated_sprite.flip_h = direction < 0.0


func _physics_process(delta: float) -> void:
	_time_alive += delta
	if _time_alive >= lifetime:
		_spawn_hit(global_position)
		queue_free()
		return

	# Rotate to face velocity direction (after portal teleport velocity may change)
	if velocity.length() > 0.01:
		var angle := velocity.angle()
		rotation = angle
		animated_sprite.flip_h = false
		animated_sprite.flip_v = absf(angle) > PI / 2.0

	var motion := velocity * delta
	var collision := move_and_collide(motion)

	if collision:
		# Check if we hit a portal surface — let the portal handle teleportation
		if _find_portal_at_collision(collision):
			return
		var collider := collision.get_collider()
		# Deal damage if the collider can receive it
		var is_enemy: bool = collider.is_in_group("enemies")
		if allow_friendly_fire or not is_enemy:
			# Prefer take_bullet_damage (enemies use this), fall back to take_damage
			if collider.has_method("take_bullet_damage"):
				collider.take_bullet_damage(damage, global_position)
			elif collider.has_method("take_damage"):
				collider.take_damage(damage, global_position)
		_spawn_hit(collision.get_position())
		queue_free()
		return


func _spawn_hit(pos: Vector2) -> void:
	var hit = hit_scene.instantiate()
	hit.global_position = pos
	get_tree().current_scene.add_child(hit)
