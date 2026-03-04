extends PortalEntity

## Portal-style 2D platformer character controller.
## Designed around the core Portal mechanic: momentum is preserved through portals.
## Air control is intentionally weak so portal flings carry the player properly.
## Includes coyote time and jump buffering for responsive platforming feel.

@export var SPEED: float = 150.0
@export var SPRINT_MULTIPLIER: float = 1.5
@export var JUMP_VELOCITY: float = -400.0
@export var MAX_SPEED: float = 1500.0

@export_group("Acceleration")
@export var GROUND_ACCELERATION: float = 20.0
@export var AIR_ACCELERATION: float = 5.0
@export var FLING_AIR_ACCELERATION: float = 1.0

@export_group("Friction")
@export var GROUND_FRICTION: float = 1000.0  # higher = stops faster on ground
@export var AIR_FRICTION: float = 1.2
@export var FLING_AIR_FRICTION: float = 0.15

@export_group("Jump Feel")
@export var COYOTE_TIME: float = 0.12
@export var JUMP_BUFFER_TIME: float = 0.1

@export_group("Health")
@export var max_hp: int = 100
@export var default_hazard_damage: int = 10
@export var invincibility_grace: float = 0.3
@export var knockback_force: Vector2 = Vector2(60.0, -75.0)

@export_group("Out of Bounds")
## How far past the screen edge (in pixels) before the player respawns
@export var oob_fall_y: float = 3000.0        # respawn if player falls below this Y
@export var oob_left_x: float = -3000.0       # optional left boundary
@export var oob_right_x: float = 3000.0      # optional right boundary

# Sound list
const footstep_streams: Array[AudioStream] = [
	preload("res://character/sounds/footstep1.wav"),
	preload("res://character/sounds/footstep2.wav"),
	preload("res://character/sounds/footstep3.wav"),
	preload("res://character/sounds/footstep4.wav"),
	preload("res://character/sounds/footstep5.wav"),
	preload("res://character/sounds/footstep6.wav"),
	preload("res://character/sounds/footstep7.wav"),
	preload("res://character/sounds/footstep8.wav")
]
const damage_streams: Array[AudioStream] = [
	preload("res://character/sounds/damage1.wav"),
	preload("res://character/sounds/damage2.wav"),
	preload("res://character/sounds/damage3.wav"),
	preload("res://character/sounds/damage4.wav"),
	preload("res://character/sounds/damage5.wav"),
	preload("res://character/sounds/damage6.wav"),
	preload("res://character/sounds/damage7.wav"),
	preload("res://character/sounds/damage8.wav"),
	preload("res://character/sounds/damage9.wav"),
	preload("res://character/sounds/damage10.wav")
]
const death_vo: AudioStream = preload("res://character/sounds/death.wav")
const jumping_vo: AudioStream = preload("res://character/sounds/jumping_vo.wav")
const landing_vo: AudioStream = preload("res://character/sounds/landing_vo.wav")
const aggro_vo: AudioStream = preload("res://character/sounds/aggro.wav")
const low_health_stream: AudioStream = preload("res://character/sounds/low_health.wav")

@onready var sprite: Sprite2D = $Player
@onready var animation_tree: AnimationTree = $AnimationTree
@onready var _state_machine: AnimationNodeStateMachinePlayback = null
@onready var _footstep_player: AudioStreamPlayer = $Footsteps
@onready var _vo_player: AudioStreamPlayer = $Voiceover

var start_position: Vector2
var current_hp: int
var _coyote_timer: float = 0.0
var _jump_buffer_timer: float = 0.0
var _was_grounded: bool = false
var _is_invincible: bool = false
var _invincibility_timer: float = 0.0
var _is_knocked_back: bool = false
var _knockback_timer: float = 0.0
var _is_dying: bool = false
var _die_timer: float = 0.0
var _respawn_delay_timer: float = 0.0
var _awaiting_respawn: bool = false
var _is_landing: bool = false
var _landing_timer: float = 0.0
var _was_airborne: bool = false
var low_health_cooldown: float = 8.0
var _vo_busy_timer: float = 0.0
var _aggro_count: int = 0
var _vo_queue: Array[AudioStream] = []

# ── Audio state ──────────────────────────────────────────────────────────────
## Cycles through footstep1–8 in order (wraps around)
var _footstep_index: int = 0
## Counts up while the player is moving on the ground
var _footstep_timer: float = 0.0
## Set to true once the first footstep offset (0.2 s) has fired this stride
var _footstep_first_hit: bool = false
var _low_health_cooldown_timer: float = 0.0

# ── Polyphonic playback handles ───────────────────────────────────────────────
var _footstep_playback: AudioStreamPlaybackPolyphonic
var _vo_playback: AudioStreamPlaybackPolyphonic

func _ready() -> void:
	current_hp = max_hp
	animation_tree.active = true
	_state_machine = animation_tree.get("parameters/playback")
	start_position = position
	print("Player spawned — HP: ", current_hp, " / ", max_hp)

	# Grab polyphonic playback objects so we can fire one-shots freely
	_footstep_player.play()
	_footstep_playback = _footstep_player.get_stream_playback()

	_vo_player.play()
	_vo_playback = _vo_player.get_stream_playback()

## Override: clear coyote time and jump buffer on portal exit so the player
## can't spam-jump out of a fling.
func notify_portal_launch() -> void:
	super.notify_portal_launch()
	_coyote_timer = 0.0
	_jump_buffer_timer = 0.0

func _physics_process(delta: float) -> void:	
	
	if _is_invincible:
		_invincibility_timer -= delta
		# Blink the sprite to indicate invincibility
		sprite.modulate.a = 0.3 if fmod(_invincibility_timer, 0.16) < 0.08 else 1.0
		if _invincibility_timer <= 0.0:
			_is_invincible = false
			sprite.modulate.a = 1.0

	# Tick down low-health VO cooldown
	if _low_health_cooldown_timer > 0.0:
		_low_health_cooldown_timer -= delta

	if _vo_busy_timer > 0.0:
		_vo_busy_timer -= delta

	# --- Waiting for respawn after die animation ---
	if _awaiting_respawn:
		_respawn_delay_timer -= delta
		if _respawn_delay_timer <= 0.0:
			_finish_die()
		return

	# --- Die animation in progress: only apply gravity + slide, no input ---
	if _is_dying:
		_die_timer -= delta
		if not is_grounded:
			velocity += get_gravity() * delta
		custom_move_and_slide(delta)
		if _die_timer <= 0.0:
			# Die animation done — freeze and wait for respawn delay
			_is_dying = false
			_awaiting_respawn = true
			_respawn_delay_timer = 0.6
			velocity = Vector2.ZERO
		return

	# --- Knockback animation in progress: apply gravity but no player input ---
	if _is_knocked_back:
		_knockback_timer -= delta
		if not is_grounded:
			velocity += get_gravity() * delta
		custom_move_and_slide(delta)
		if _knockback_timer <= 0.0:
			_is_knocked_back = false
			if _state_machine:
				_state_machine.travel("Move")
		return

	# --- Land animation in progress: hold position, no input ---
	if _is_landing:
		_landing_timer -= delta
		if not is_grounded:
			velocity += get_gravity() * delta
		else:
			velocity.x = 0.0
		custom_move_and_slide(delta)
		if _landing_timer <= 0.0:
			_is_landing = false
			if _state_machine:
				_state_machine.travel("Move")
		_was_grounded = is_grounded
		_was_airborne = not is_grounded
		return

	# --- Coyote time tracking ---
	if is_grounded:
		_coyote_timer = COYOTE_TIME
	else:
		_coyote_timer -= delta

	# --- Jump buffer tracking ---
	if Input.is_action_just_pressed("Up"):
		_jump_buffer_timer = JUMP_BUFFER_TIME
	else:
		_jump_buffer_timer -= delta

	# --- Gravity ---
	if not is_grounded:
		velocity += get_gravity() * delta

	# --- Jump (with coyote time + buffer) ---
	var can_jump := _coyote_timer > 0.0 or is_grounded
	if can_jump and _jump_buffer_timer > 0.0:
		velocity.y = JUMP_VELOCITY
		_coyote_timer = 0.0
		_jump_buffer_timer = 0.0
		launched_by_portal = false
		_play_vo(jumping_vo)      # ← jumping voiceover

	# --- Horizontal movement ---
	var direction := Input.get_axis("Left", "Right")
	var is_sprinting := Input.is_action_pressed("Sprint") and is_grounded
	var target_speed := direction * SPEED * (SPRINT_MULTIPLIER if is_sprinting else 1.0)

	if is_grounded:
		if direction != 0:
			velocity.x = lerp(velocity.x, target_speed, minf(GROUND_ACCELERATION * delta, 1.0))
		if direction == 0:
			velocity.x = move_toward(velocity.x, 0.0, GROUND_FRICTION * delta)
	else:
		var air_accel := FLING_AIR_ACCELERATION if launched_by_portal else AIR_ACCELERATION
		var air_fric := FLING_AIR_FRICTION if launched_by_portal else AIR_FRICTION

		if direction != 0:
			velocity.x = lerp(velocity.x, target_speed, minf(air_accel * delta, 1.0))
		else:
			velocity.x = move_toward(velocity.x, 0.0, air_fric * delta)

	# --- Speed cap ---
	velocity = velocity.limit_length(MAX_SPEED)

	# --- Sprite flipping ---
	if velocity.x > 0.1:
		sprite.flip_h = false
	elif velocity.x < -0.1:
		sprite.flip_h = true

	# --- Animation ---
	if _state_machine:
		if not is_grounded:
			if velocity.y < -50.0:
				_travel_if_not("JumpRise")
			elif velocity.y < 50.0:
				_travel_if_not("JumpMid")
			else:
				_travel_if_not("JumpFall")
		#####################
		#   Disabled for now...
		#####################
		# elif _was_airborne:
		# 	# Just landed this frame — play Land and lock input
		# 	_is_landing = true
		# 	_landing_timer = 0.2
		# 	_state_machine.travel("Land")
		# 	_play_footstep()               # ← footstep on landing impact
		# 	_play_vo(landing_vo)           # ← landing voiceover
		else:
			var current := _state_machine.get_current_node()
			if current != "Land" and current != "Move":
				_state_machine.travel("Move")

	if direction != 0:
		animation_tree.set("parameters/Move/blend_position", 1.0 if is_sprinting else 0.5)
	else:
		animation_tree.set("parameters/Move/blend_position", 0.0)

	# --- Footstep timing while moving on ground ---
	_tick_footsteps(delta, direction, is_sprinting)

	# --- Move ---
	custom_move_and_slide(delta)

	# --- Out-of-bounds check ---
	_check_out_of_bounds()

	# --- Track grounded state change ---
	_was_grounded = is_grounded
	_was_airborne = not is_grounded

# ── Footstep timing ──────────────────────────────────────────────────────────
## Drives timed footstep sounds while walking or sprinting on the ground.
##
## Walk  → footstep at t = 0.2 s, then every 0.4 s  (stride: 0.0 → 0.2 → 0.4 → 0.6 → …)
## Sprint → footstep at t = 0.2 s, then every 0.8 s  (stride: 0.0 → 0.2 → 1.0 → 1.8 → …)
func _tick_footsteps(delta: float, direction: float, is_sprinting: bool) -> void:
	if not is_grounded or direction == 0.0:
		_footstep_timer = 0.0
		_footstep_first_hit = false
		return

	var first_hit    := 0.0666 if is_sprinting else 0.2
	var second_hit   := 0.2    if is_sprinting else 0.4
	var cycle_length := 0.2    if is_sprinting else 0.4

	_footstep_timer += delta

	if not _footstep_first_hit and _footstep_timer >= first_hit:
		_footstep_first_hit = true
		_play_footstep()

	if _footstep_timer >= second_hit:
		_play_footstep()
		_footstep_timer -= cycle_length
		_footstep_first_hit = false

# ── Audio helpers ────────────────────────────────────────────────────────────

## Play the next footstep in the round-robin sequence (footstep1–8).
func _play_footstep() -> void:
	if footstep_streams.is_empty() or _footstep_playback == null:
		return
	var stream := footstep_streams[_footstep_index % footstep_streams.size()]
	_footstep_index = (_footstep_index + 1) % footstep_streams.size()
	if stream:
		_footstep_playback.play_stream(stream)

## Play a random damage VO (damage1–10).
func _play_damage_vo() -> void:
	if damage_streams.is_empty() or _vo_playback == null:
		return
	var stream := damage_streams[randi() % damage_streams.size()]
	if stream:
		_vo_playback.play_stream(stream)

## Play a single VO stream on the voiceover bus (jump, land, low_health).
func _play_vo(stream: AudioStream) -> void:
	if stream == null or _vo_playback == null:
		return
	_vo_playback.play_stream(stream)
	_vo_busy_timer = stream.get_length()

## Check health and play low_health VO if at or below 30 % (with cooldown).
func _check_low_health_audio() -> void:
	if float(current_hp) / float(max_hp) <= 0.3 \
	and _low_health_cooldown_timer <= 0.0 \
	and _vo_busy_timer <= 0.0:
		_play_vo(low_health_stream)
		_low_health_cooldown_timer = low_health_cooldown

# ── Damage / combat ──────────────────────────────────────────────────────────

## Called by an enemy when it starts aggroing the player.
func on_enemy_aggro() -> void:
	_aggro_count += 1
	print("Enemy aggroed! Current aggro count: ", _aggro_count)
	# Only play the VO on the first enemy — ignore if already being chased
	if _aggro_count == 1:
		_play_vo(aggro_vo)

## Called by an enemy when it stops aggroing (dies, loses sight, etc.)
func on_enemy_deaggro() -> void:
	_aggro_count = maxi(_aggro_count - 1, 0)
	print("Enemy deaggroed — remaining aggro count: ", _aggro_count)

## Called when a hazard Area2D overlaps the character's HurtBox.
func _on_hurt_box_area_entered(area: Area2D) -> void:
	if _is_invincible or _is_dying:
		return
	var damage: int = default_hazard_damage
	if area.get("damage") != null:
		damage = area.get("damage")
	take_damage(damage, area.global_position)

## Apply damage to the character, play hit animation, and start invincibility.
func take_damage(amount: int, hit_source_pos: Vector2 = global_position, knockback: bool = true) -> void:
	if _is_invincible or _is_dying:
		return
	current_hp -= amount
	print("Player hit! -", amount, " HP  →  HP: ", current_hp, " / ", max_hp)
	_play_damage_vo()          # ← damage voiceover
	if current_hp <= 0:
		_start_die()
	else:
		_check_low_health_audio()   # ← low health cue (only if still alive)
		if knockback:
			_start_knockback(hit_source_pos)
		else:
			_start_invincibility(invincibility_grace)

## Begin the knockback animation and apply knockback velocity.
func _start_knockback(hit_source_pos: Vector2) -> void:
	_is_knocked_back = true
	_knockback_timer = 0.9
	var kb_dir: float = sign(global_position.x - hit_source_pos.x)
	if kb_dir == 0:
		kb_dir = -1.0 if sprite.flip_h else 1.0
	velocity = Vector2(kb_dir * knockback_force.x, knockback_force.y)
	_start_invincibility(0.9 + invincibility_grace)
	if _state_machine:
		_state_machine.travel("Knockback")

## Begin the die animation.
func _start_die() -> void:
	_is_dying = true
	_die_timer = 0.63
	velocity = Vector2(0.0, knockback_force.y * 0.5)
	_start_invincibility(999.0)
	if _state_machine:
		_state_machine.travel("Die")

## Called after die animation + respawn delay.
func _finish_die() -> void:
	print("Player died! Respawning...")
	_awaiting_respawn = false
	_respawn()

## Shared respawn logic.
func _respawn() -> void:
	current_hp = max_hp
	position = start_position
	velocity = Vector2.ZERO
	launched_by_portal = false
	_is_dying = false
	_awaiting_respawn = false
	_is_knocked_back = false
	_is_landing = false
	_footstep_timer = 0.0
	_footstep_first_hit = false
	_low_health_cooldown_timer = 0.0
	_aggro_count = 0
	sprite.modulate.a = 1.0
	_start_invincibility(1.0)
	if _state_machine:
		_state_machine.travel("Move")
	print("HP restored: ", current_hp, " / ", max_hp)

## Activate invincibility for the given duration.
func _start_invincibility(duration: float) -> void:
	_is_invincible = true
	_invincibility_timer = duration

## Travel to a state only if not already in it.
func _travel_if_not(state_name: String) -> void:
	if _state_machine and _state_machine.get_current_node() != state_name:
		_state_machine.travel(state_name)

## Respawn the player if they leave the map
func _check_out_of_bounds() -> void:
	if global_position.y > oob_fall_y \
	or global_position.x < oob_left_x \
	or global_position.x > oob_right_x:
		print("Player out of bounds at ", global_position, " — respawning.")
		_respawn()
