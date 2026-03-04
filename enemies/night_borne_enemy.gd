extends Enemy

enum State { IDLE, ROAM, CHASE, ATTACK, HURT, DEATH }

# ── Stats ──────────────────────────────────────────────────────────────────────
@export_group("Stats")
@export var attack_damage: int = 20

# ── Timers ─────────────────────────────────────────────────────────────────────
@export_group("Timers")
@export var attack_cooldown: float = 1.5

# ── Attack Window ──────────────────────────────────────────────────────────────
@export_group("Attack Window")
@export var damage_window_start: float = 0.58
@export var damage_window_end: float = 0.67
@export var attack_range: float = 45.0

# Animation durations (must match AnimationPlayer)
const SLASH_DURATION: float = 0.867
const HURT_DURATION: float = 0.5
const DEATH_DURATION: float = 2.0

# ── Internal State ─────────────────────────────────────────────────────────────
var state: State = State.IDLE

var _attack_cooldown_timer: float = 0.0
var _attack_elapsed: float = 0.0
var _has_dealt_damage: bool = false

var _hurt_timer: float = 0.0
var _death_timer: float = 0.0

# ── Node References ────────────────────────────────────────────────────────────
@onready var sprite: Sprite2D = $Sprite2D
@onready var anim_player: AnimationPlayer = $AnimationPlayer
@onready var deaggro_area: Area2D = $DeaggroArea
@onready var hit_box: Area2D = $HitBox
@onready var hurt_box: Area2D = $HurtBox


# ═══════════════════════════════════════════════════════════════════════════════
#  Lifecycle
# ═══════════════════════════════════════════════════════════════════════════════

func _ready() -> void:
	super._ready()

	deaggro_area.body_entered.connect(_on_deaggro_body_entered)
	deaggro_area.body_exited.connect(_on_deaggro_body_exited)
	hit_box.body_entered.connect(_on_hitbox_body_entered)

	hit_box.monitorable = false
	_set_hitbox_active(false)

	_enter_state(State.IDLE)
	print("NightBorne spawned — HP: ", current_hp, " / ", max_hp)


func _physics_process(delta: float) -> void:

	if not is_on_floor():
		velocity += get_gravity() * delta

	if _attack_cooldown_timer > 0.0:
		_attack_cooldown_timer -= delta

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

	if _is_at_edge(dir_to_target) or _is_wall_ahead(dir_to_target):
		velocity.x = 0.0
	elif dist > attack_range:
		velocity.x = dir_to_target * chase_speed
	else:
		velocity.x = 0.0

	if dist <= attack_range and _attack_cooldown_timer <= 0.0:
		_enter_state(State.ATTACK)


func _process_attack(delta: float) -> void:
	velocity.x = 0.0
	_attack_elapsed += delta

	var in_window := _attack_elapsed >= damage_window_start and _attack_elapsed <= damage_window_end
	if in_window and not _has_dealt_damage:
		_set_hitbox_active(true)
		_deal_attack_damage()
	elif _attack_elapsed > damage_window_end:
		_set_hitbox_active(false)

	if _attack_elapsed >= SLASH_DURATION:
		_finish_attack()


func _process_hurt(delta: float) -> void:
	velocity.x = 0.0
	_hurt_timer -= delta
	if _hurt_timer <= 0.0:
		if _has_los and _valid_target():
			_enter_state(State.CHASE)
		else:
			_enter_state(State.IDLE)


func _process_death(delta: float) -> void:
	velocity.x = 0.0
	_death_timer -= delta
	if _death_timer <= 0.0:
		queue_free()


# ═══════════════════════════════════════════════════════════════════════════════
#  State Transitions
# ═══════════════════════════════════════════════════════════════════════════════

func _enter_state(new_state: State) -> void:
	# Notify before state changes
	if new_state == State.CHASE and state != State.CHASE and _has_los:
		_notify_aggro()
	if new_state != State.CHASE and state == State.CHASE:
		_notify_deaggro()

	state = new_state
	match new_state:
		State.IDLE:
			_idle_timer = randf_range(roam_idle_min, roam_idle_max)
			anim_player.play("Idle")
		State.ROAM:
			_roam_direction = [-1.0, 1.0].pick_random()
			_roam_timer = randf_range(roam_walk_min, roam_walk_max)
			_update_facing(_roam_direction)
			anim_player.play("Run")
		State.CHASE:
			_deaggro_timer = deaggro_time
			anim_player.play("Run")
		State.ATTACK:
			velocity.x = 0.0
			_attack_elapsed = 0.0
			_has_dealt_damage = false
			_set_hitbox_active(true)
			anim_player.play("Slash")
		State.HURT:
			_hurt_timer = HURT_DURATION
			_set_hitbox_active(false)
			anim_player.play("Hurt")
		State.DEATH:
			_death_timer = DEATH_DURATION
			_set_hitbox_active(false)
			collision_layer = 0
			collision_mask = 0
			anim_player.play("Death")


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
	print("NightBorne hit! -", amount, " HP  →  ", current_hp, " / ", max_hp)
	if current_hp <= 0:
		current_hp = 0
		_enter_state(State.DEATH)
	else:
		_enter_state(State.HURT)


# ═══════════════════════════════════════════════════════════════════════════════
#  Damage — Dealing
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
	if _attack_elapsed < damage_window_start or _attack_elapsed > damage_window_end:
		return
	if body == self or body.is_in_group("enemies"):
		return
	if body.has_method("take_damage"):
		body.take_damage(attack_damage, global_position)
		_has_dealt_damage = true


# ═══════════════════════════════════════════════════════════════════════════════
#  Detection — Deaggro Area
# ═══════════════════════════════════════════════════════════════════════════════

func _on_deaggro_body_entered(body: Node2D) -> void:
	if body == self or body.is_in_group("enemies") or body.is_in_group("turret_bullets"):
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
	sprite.flip_h = facing < 0.0
	hit_box.scale.x = absf(hit_box.scale.x) * signf(facing)


func _set_hitbox_active(active: bool) -> void:
	hit_box.monitoring = active
	for child in hit_box.get_children():
		if child is CollisionShape2D:
			child.disabled = not active