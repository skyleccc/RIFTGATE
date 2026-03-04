extends Enemy

## Striker Enemy — patrol / chase melee+ranged AI with dash.
## Strike animation: frames 2-4, 6-7 = melee hitbox; frame 13 = bullet spawn.
## Only turret bullets hurt it.

enum State { IDLE, ROAM, CHASE, ATTACK, HURT, DEATH, DASH }

# ── Stats ──────────────────────────────────────────────────────────────────────
@export_group("Attack")
@export var attack_damage: int = 20
@export var attack_range: float = 45.0
@export var attack_cooldown: float = 1.5
@export var bullet_speed: float = 200.0
@export var bullet_lifetime: float = 2.0
@export var bullet_damage: int = 10

# ── Dash ───────────────────────────────────────────────────────────────────────
@export_group("Dash")
@export var dash_speed: float = 300.0
@export var dash_cooldown: float = 4.0
@export var dash_range_min: float = 80.0
@export var dash_range_max: float = 180.0

# ── Strike frame constants (0-indexed) ─────────────────────────────────────────
const MELEE_FRAMES: Array[int] = [2, 3, 6, 7]
const BULLET_FRAME: int = 13
const RETARGET_FRAMES: Array[int] = [2, 6, 12]

# Preloads
var bullet_scene: PackedScene = preload("res://enemies/StrikerBullet.tscn")

# ── Internal State ─────────────────────────────────────────────────────────────
var state: State = State.IDLE

var _attack_cooldown_timer: float = 0.0
var _has_dealt_damage: bool = false
var _has_spawned_bullet: bool = false

var _dash_cooldown_timer: float = 0.0
var _dash_direction: float = 1.0

# ── Node References ────────────────────────────────────────────────────────────
@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var hit_box: Area2D = $HitBox
@onready var hurt_box: Area2D = $HurtBox
@onready var bullet_spawn: Marker2D = $BulletSpawn
@onready var deaggro_area: Area2D = $DeaggroArea


# ═══════════════════════════════════════════════════════════════════════════════
#  Lifecycle
# ═══════════════════════════════════════════════════════════════════════════════

func _ready() -> void:
	super._ready()

	# Disable looping on one-shot animations
	var sf := animated_sprite.sprite_frames
	for anim_name in ["Death", "Struck", "Strike", "Dash"]:
		if sf.has_animation(anim_name):
			sf.set_animation_loop(anim_name, false)

	animated_sprite.frame_changed.connect(_on_frame_changed)
	animated_sprite.animation_finished.connect(_on_animation_finished)
	hit_box.body_entered.connect(_on_hitbox_body_entered)

	hit_box.monitorable = false
	_set_hitbox_active(false)

	deaggro_area.body_entered.connect(_on_deaggro_body_entered)
	deaggro_area.body_exited.connect(_on_deaggro_body_exited)

	_enter_state(State.IDLE)
	print("Striker spawned — HP: ", current_hp, " / ", max_hp)


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity += get_gravity() * delta

	if _attack_cooldown_timer > 0.0:
		_attack_cooldown_timer -= delta
	if _dash_cooldown_timer > 0.0:
		_dash_cooldown_timer -= delta

	_update_los()

	match state:
		State.IDLE:
			_process_idle(delta)
		State.ROAM:
			_process_roam(delta)
		State.CHASE:
			_process_chase(delta)
		State.ATTACK:
			_process_attack(delta)
		State.HURT:
			_process_hurt(delta)
		State.DEATH:
			_process_death(delta)
		State.DASH:
			_process_dash(delta)

	if state != State.DEATH:
		move_and_slide()


# ═══════════════════════════════════════════════════════════════════════════════
#  State Processors
# ═══════════════════════════════════════════════════════════════════════════════

func _process_idle(delta: float) -> void:
	velocity.x = 0.0
	_idle_timer -= delta

	if _has_los and _valid_target():
		_enter_state(State.CHASE)
		return

	if _idle_timer <= 0.0:
		_enter_state(State.ROAM)


func _process_roam(delta: float) -> void:
	_roam_timer -= delta

	if _has_los and _valid_target():
		_enter_state(State.CHASE)
		return

	if _is_at_edge(_roam_direction) or _is_wall_ahead(_roam_direction):
		_roam_direction = -_roam_direction
		_update_facing(_roam_direction)

	velocity.x = _roam_direction * move_speed

	if _roam_timer <= 0.0:
		_enter_state(State.IDLE)


func _process_chase(delta: float) -> void:
	if not _valid_target():
		_enter_state(State.IDLE)
		return

	if not _player_in_deaggro or not _has_los:
		_deaggro_timer -= delta
		if _deaggro_timer <= 0.0:
			target = null
			_enter_state(State.IDLE)
			return
	else:
		_deaggro_timer = deaggro_time

	var dir_to_target := signf(target.global_position.x - global_position.x)
	var dist := absf(target.global_position.x - global_position.x)

	_update_facing(dir_to_target)

	if _dash_cooldown_timer <= 0.0 and dist >= dash_range_min and dist <= dash_range_max:
		_enter_state(State.DASH)
		return

	if _is_at_edge(dir_to_target) or _is_wall_ahead(dir_to_target):
		velocity.x = 0.0
	elif dist > attack_range:
		velocity.x = dir_to_target * chase_speed
	else:
		velocity.x = 0.0

	if dist <= attack_range and _attack_cooldown_timer <= 0.0:
		_enter_state(State.ATTACK)


func _process_attack(_delta: float) -> void:
	velocity.x = 0.0
	# Frame-based logic handled by _on_frame_changed and _on_animation_finished


func _process_hurt(_delta: float) -> void:
	velocity.x = 0.0
	# Handled by _on_animation_finished


func _process_death(_delta: float) -> void:
	velocity.x = 0.0
	# Handled by _on_animation_finished


func _process_dash(_delta: float) -> void:
	if _is_at_edge(_dash_direction) or _is_wall_ahead(_dash_direction):
		velocity.x = 0.0
	else:
		velocity.x = _dash_direction * dash_speed

	if _valid_target():
		var dist := absf(target.global_position.x - global_position.x)
		if dist <= attack_range and _attack_cooldown_timer <= 0.0:
			_enter_state(State.ATTACK)
			return


# ═══════════════════════════════════════════════════════════════════════════════
#  Animation Callbacks
# ═══════════════════════════════════════════════════════════════════════════════

func _on_frame_changed() -> void:
	if state != State.ATTACK:
		return

	var frame := animated_sprite.frame

	if frame in RETARGET_FRAMES and _valid_target():
		var dir_to_target := signf(target.global_position.x - global_position.x)
		_update_facing(dir_to_target)

	if frame in MELEE_FRAMES:
		if not _has_dealt_damage:
			_set_hitbox_active(true)
			_deal_attack_damage()
	else:
		_set_hitbox_active(false)

	if frame == BULLET_FRAME and not _has_spawned_bullet:
		_has_spawned_bullet = true
		_spawn_bullet()


func _on_animation_finished() -> void:
	match state:
		State.ATTACK:
			_finish_attack()
		State.HURT:
			if _has_los and _valid_target():
				_enter_state(State.CHASE)
			else:
				_enter_state(State.IDLE)
		State.DEATH:
			queue_free()
		State.DASH:
			_dash_cooldown_timer = dash_cooldown
			if _has_los and _valid_target():
				_enter_state(State.CHASE)
			else:
				_enter_state(State.IDLE)


# ═══════════════════════════════════════════════════════════════════════════════
#  State Transitions
# ═══════════════════════════════════════════════════════════════════════════════

func _enter_state(new_state: State) -> void:
	state = new_state
	match new_state:
		State.IDLE:
			_idle_timer = randf_range(roam_idle_min, roam_idle_max)
			animated_sprite.play("Idle")
		State.ROAM:
			_roam_direction = [-1.0, 1.0].pick_random()
			_roam_timer = randf_range(roam_walk_min, roam_walk_max)
			_update_facing(_roam_direction)
			animated_sprite.play("Run")
		State.CHASE:
			_deaggro_timer = deaggro_time
			animated_sprite.play("Run")
		State.ATTACK:
			velocity.x = 0.0
			_has_dealt_damage = false
			_has_spawned_bullet = false
			_set_hitbox_active(false)
			animated_sprite.play("Strike")
		State.HURT:
			_set_hitbox_active(false)
			animated_sprite.play("Struck")
		State.DEATH:
			_set_hitbox_active(false)
			collision_layer = 0
			collision_mask = 0
			animated_sprite.play("Death")
		State.DASH:
			if _valid_target():
				_dash_direction = signf(target.global_position.x - global_position.x)
			else:
				_dash_direction = facing
			_update_facing(_dash_direction)
			animated_sprite.play("Dash")


func _finish_attack() -> void:
	_set_hitbox_active(false)
	_attack_cooldown_timer = attack_cooldown
	if _has_los and _valid_target():
		_enter_state(State.CHASE)
	else:
		_enter_state(State.IDLE)


# ═══════════════════════════════════════════════════════════════════════════════
#  Damage — Receiving
# ═══════════════════════════════════════════════════════════════════════════════

func take_bullet_damage(amount: int, _hit_source_pos: Vector2 = global_position) -> void:
	if state == State.DEATH:
		return
	current_hp -= amount
	print("Striker hit! -", amount, " HP  →  ", current_hp, " / ", max_hp)
	if current_hp <= 0:
		current_hp = 0
		_enter_state(State.DEATH)
	else:
		_enter_state(State.HURT)


# ═══════════════════════════════════════════════════════════════════════════════
#  Damage — Dealing (Melee)
# ═══════════════════════════════════════════════════════════════════════════════

func _deal_attack_damage() -> void:
	for body in hit_box.get_overlapping_bodies():
		if body == self or body.is_in_group("enemies"):
			continue
		if body.has_method("take_damage"):
			body.take_damage(attack_damage, global_position)
			_has_dealt_damage = true
			return


func _on_hitbox_body_entered(body: Node2D) -> void:
	if state != State.ATTACK or _has_dealt_damage:
		return
	var frame := animated_sprite.frame
	if frame not in MELEE_FRAMES:
		return
	if body == self or body.is_in_group("enemies"):
		return
	if body.has_method("take_damage"):
		body.take_damage(attack_damage, global_position)
		_has_dealt_damage = true


# ═══════════════════════════════════════════════════════════════════════════════
#  Damage — Dealing (Ranged)
# ═══════════════════════════════════════════════════════════════════════════════

func _spawn_bullet() -> void:
	var bullet := bullet_scene.instantiate()
	if bullet == null:
		return
	get_tree().current_scene.add_child(bullet)
	bullet.global_position = global_position + Vector2(bullet_spawn.position.x * facing, bullet_spawn.position.y)
	bullet.direction = facing
	bullet.speed = bullet_speed
	bullet.lifetime = bullet_lifetime
	bullet.damage = bullet_damage
	bullet.add_collision_exception_with(self)
	bullet.initialize()


# ═══════════════════════════════════════════════════════════════════════════════
#  Detection — Deaggro Area
# ═══════════════════════════════════════════════════════════════════════════════

func _on_deaggro_body_entered(body: Node2D) -> void:
	if body == self or body.is_in_group("enemies") or body.is_in_group("turret_bullets") or body.is_in_group("striker_bullets"):
		return
	if body.has_method("take_damage"):
		_player_in_deaggro = true
		if target == null:
			target = body


func _on_deaggro_body_exited(body: Node2D) -> void:
	if body == target:
		_player_in_deaggro = false
		_deaggro_timer = deaggro_time


# ═══════════════════════════════════════════════════════════════════════════════
#  Helpers
# ═══════════════════════════════════════════════════════════════════════════════

func _update_facing(dir: float) -> void:
	if dir == 0.0:
		return
	facing = dir
	animated_sprite.flip_h = facing < 0.0
	hit_box.scale.x = absf(hit_box.scale.x) * signf(facing)


func _set_hitbox_active(active: bool) -> void:
	hit_box.monitoring = active
	for child in hit_box.get_children():
		if child is CollisionShape2D:
			child.disabled = not active
