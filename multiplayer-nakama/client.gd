extends Control
class_name nakamaMultiplayerClient

const NAKAMA_SCRIPT := preload("res://multiplayer-nakama/addons/com.heroiclabs.nakama/Nakama.gd")
const CHARACTER_SCENE := preload("res://character/CharacterModel.tscn")
const PLAYER_SYNC_SCRIPT := preload("res://multiplayer-nakama/sync/player_sync.gd")
const ENEMY_SYNC_SCRIPT := preload("res://multiplayer-nakama/sync/enemy_sync.gd")
const PORTAL_SYNC_SCRIPT := preload("res://multiplayer-nakama/sync/portal_sync.gd")
const OP_PLAYER_STATE := 1
const SYNC_INTERVAL := 0.08

var session : NakamaSession
var client : NakamaClient
var socket : NakamaSocket
var nakama : Node
var current_match_id : String = ""
var local_session_id : String = ""
var in_match := false
var world_root : Node2D
var local_character : Node2D
var remote_players := {}
var peer_session_ids := {}
var remote_portals := {}
var peer_hp := {}
var last_sent_position := Vector2(-99999, -99999)
var sync_accum := 0.0
var local_hp_current := -1
var local_hp_max := -1
var player_sync := PLAYER_SYNC_SCRIPT.new()
var enemy_sync := ENEMY_SYNC_SCRIPT.new()
var portal_sync := PORTAL_SYNC_SCRIPT.new()

@onready var status_label : Label = $PanelContainer/VBoxContainer/StatusLabel
@onready var match_id_input : LineEdit = $PanelContainer/VBoxContainer/MatchIdInput
@onready var create_match_button : Button = $PanelContainer/VBoxContainer/ButtonRow/CreateMatchButton
@onready var join_match_button : Button = $PanelContainer/VBoxContainer/ButtonRow/JoinMatchButton
var players_hp_label : Label

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	set_status("Connecting to Nakama...")
	create_match_button.disabled = true
	join_match_button.disabled = true

	nakama = NAKAMA_SCRIPT.new()
	add_child(nakama)

	client = nakama.create_client("defaultkey", "127.0.0.1", 7350, "http")
	session = await client.authenticate_email_async("test@gmail.com", "password")
	if session.is_exception() or !session.is_valid():
		set_status("Auth failed. Check credentials/server.")
		push_error("Nakama auth failed: %s" % str(session))
		return

	socket = nakama.create_socket_from(client)

	socket.connected.connect(onSocketConnected)
	socket.closed.connect(onSocketClosed)
	socket.received_error.connect(onSocketError)
	
	socket.received_match_presence.connect(onMatchPresence)
	socket.received_match_state.connect(onMatchState)

	var conn = await socket.connect_async(session)
	if conn.is_exception():
		set_status("Socket connection failed.")
		push_error("Nakama socket connect failed: %s" % str(conn.get_exception()))
		return

	create_match_button.disabled = false
	join_match_button.disabled = false
	set_status("Connected. Create or join a match.")

	create_match_button.pressed.connect(_on_create_match_pressed)
	join_match_button.pressed.connect(_on_join_match_pressed)
	match_id_input.text_submitted.connect(_on_match_id_submitted)
	_bind_world_nodes()
	_bind_hud_nodes()
	_update_hp_hud()
	
	pass # Replace with function body.

func onSocketConnected():
	# print("Socket connected!")
	set_status("Connected to Nakama server.")

func onSocketClosed():
	# print("Socket closed!")
	set_status("Socket closed.")
	create_match_button.disabled = true
	join_match_button.disabled = true
	in_match = false
	peer_session_ids.clear()
	peer_hp.clear()
	_clear_remote_players()
	_update_hp_hud()

func onSocketError(_err):
	# print("Socket error: %s" % str(err))
	set_status("Socket error. See console.")

func onMatchPresence(presenceEvent : NakamaRTAPI.MatchPresenceEvent):
	# print("Match presence event: %s" % str(presenceEvent))
	if presenceEvent.match_id != current_match_id:
		return

	for joined in presenceEvent.joins:
		if joined.session_id == local_session_id:
			continue
		peer_session_ids[joined.session_id] = true
		_ensure_remote_player(joined.session_id)

	for left in presenceEvent.leaves:
		peer_session_ids.erase(left.session_id)
		peer_hp.erase(left.session_id)
		if remote_players.has(left.session_id):
			remote_players[left.session_id].queue_free()
			remote_players.erase(left.session_id)
		portal_sync.clear_remote_portals_for(left.session_id, remote_portals)

	_update_hp_hud()

func onMatchState(matchState : NakamaRTAPI.MatchData):
	# print("Match state event: %s" % str(matchState))
	if matchState.match_id != current_match_id:
		return
	if matchState.op_code != OP_PLAYER_STATE:
		return
	if matchState.presence == null:
		return

	var sender_session_id := matchState.presence.session_id
	if sender_session_id == local_session_id:
		return

	var json := JSON.new()
	if json.parse(matchState.data) != OK:
		return
	var parsed = json.get_data()
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var remote_player = _ensure_remote_player(sender_session_id)
	if remote_player != null and parsed.has("p") and typeof(parsed["p"]) == TYPE_DICTIONARY:
		var player_state: Dictionary = parsed["p"]
		player_sync.apply_remote_state(remote_player, player_state)
		if player_state.has("hp") or player_state.has("hpm"):
			peer_hp[sender_session_id] = {
				"hp": int(player_state.get("hp", -1)),
				"hpm": int(player_state.get("hpm", -1))
			}

	if parsed.has("po") and typeof(parsed["po"]) == TYPE_DICTIONARY and is_instance_valid(world_root):
		portal_sync.apply_remote_portals(sender_session_id, world_root, parsed["po"], remote_portals)

	if parsed.has("e") and typeof(parsed["e"]) == TYPE_ARRAY and _get_authority_session_id() == sender_session_id:
		if is_instance_valid(world_root):
			enemy_sync.apply_enemy_states(world_root, parsed["e"])

	_update_hp_hud()

func _on_create_match_pressed() -> void:
	if socket == null or !socket.is_connected_to_host():
		set_status("Not connected yet.")
		return

	set_status("Creating match...")
	var match = await socket.create_match_async()
	if match.is_exception():
		set_status("Create match failed.")
		push_error("Create match failed: %s" % str(match.get_exception()))
		return

	current_match_id = match.match_id
	match_id_input.text = current_match_id
	set_status("Created match: %s" % current_match_id)
	_enter_match(match)

func _on_join_match_pressed() -> void:
	if socket == null or !socket.is_connected_to_host():
		set_status("Not connected yet.")
		return

	var target_match_id := match_id_input.text.strip_edges()
	if target_match_id.is_empty():
		set_status("Enter a match ID first.")
		return

	set_status("Joining match...")
	var match = await socket.join_match_async(target_match_id)
	if match.is_exception():
		set_status("Join failed. Check match ID.")
		push_error("Join match failed: %s" % str(match.get_exception()))
		return

	current_match_id = match.match_id
	set_status("Joined match: %s" % current_match_id)
	_enter_match(match)

func _on_match_id_submitted(_new_text : String) -> void:
	_on_join_match_pressed()

func set_status(text : String) -> void:
	status_label.text = "Status: %s" % text

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	if !is_instance_valid(local_character):
		_bind_world_nodes()
	_bind_hud_nodes()
	_update_local_hp_from_character()
	_update_hp_hud()

	if !in_match:
		return
	if !is_instance_valid(local_character):
		return

	var moved := local_character.global_position.distance_to(last_sent_position) > 0.1

	sync_accum += delta
	if moved or sync_accum >= SYNC_INTERVAL:
		_send_local_state(false)

	_update_hp_hud()

func _enter_match(match) -> void:
	in_match = true
	current_match_id = match.match_id
	local_session_id = match.self_user.session_id
	peer_session_ids.clear()
	peer_hp.clear()
	_bind_world_nodes()
	_clear_remote_players()
	if !is_instance_valid(local_character):
		set_status("No Character node found in main scene.")
		_update_hp_hud()
		return

	for presence in match.presences:
		if presence.session_id == local_session_id:
			continue
		peer_session_ids[presence.session_id] = true
		_ensure_remote_player(presence.session_id)

	sync_accum = SYNC_INTERVAL
	last_sent_position = local_character.global_position
	_update_local_hp_from_character()
	_update_hp_hud()
	_send_local_state(true)

func _ensure_remote_player(session_id : String) -> Node2D:
	if remote_players.has(session_id):
		return remote_players[session_id]
	if !is_instance_valid(world_root):
		_bind_world_nodes()
	if !is_instance_valid(world_root):
		return null

	var remote_player := _create_character_instance("Remote_%s" % session_id, false)
	world_root.add_child(remote_player)
	if is_instance_valid(local_character):
		remote_player.global_position = local_character.global_position + Vector2(48, 0)
	remote_players[session_id] = remote_player
	return remote_player

func _clear_remote_players() -> void:
	for session_id in remote_players.keys():
		if is_instance_valid(remote_players[session_id]):
			remote_players[session_id].queue_free()
	remote_players.clear()
	portal_sync.clear_all_remote_portals(remote_portals)
	peer_hp.clear()

func _send_local_state(force : bool) -> void:
	if !in_match:
		return
	if socket == null or !socket.is_connected_to_host():
		return
	if current_match_id.is_empty():
		return
	if !is_instance_valid(local_character):
		return

	var pos := local_character.global_position
	if !force and sync_accum < SYNC_INTERVAL and pos.distance_to(last_sent_position) < 0.1:
		return

	sync_accum = 0.0
	last_sent_position = pos
	var payload := {
		"p": player_sync.capture_local_state(local_character),
		"po": portal_sync.capture_local_portal_state(local_character)
	}

	if _is_enemy_authority() and is_instance_valid(world_root):
		payload["e"] = enemy_sync.capture_enemy_states(world_root)

	socket.send_match_state_async(current_match_id, OP_PLAYER_STATE, JSON.stringify(payload))

func _bind_world_nodes() -> void:
	var scene = get_tree().current_scene
	if scene == null:
		return
	if scene is Node2D:
		world_root = scene

	local_character = scene.find_child("Character", true, false) as Node2D

func _bind_hud_nodes() -> void:
	if is_instance_valid(players_hp_label):
		return
	var scene = get_tree().current_scene
	if scene == null:
		return
	players_hp_label = scene.find_child("PlayersHpLabel", true, false) as Label

func _create_character_instance(node_name : String, is_local : bool) -> Node2D:
	var character = CHARACTER_SCENE.instantiate() as Node2D
	character.name = node_name
	character.set_script(null)

	if character.has_node("Camera2D"):
		var cam = character.get_node("Camera2D")
		if cam is Camera2D:
			cam.enabled = false

	if character.has_node("PortalGun") and !is_local:
		character.get_node("PortalGun").visible = false

	if character.has_node("HurtBox"):
		character.get_node("HurtBox").queue_free()
	if character.has_node("EnvCollisionBox"):
		character.get_node("EnvCollisionBox").queue_free()

	if character.has_node("Player"):
		var sprite = character.get_node("Player")
		if sprite is Sprite2D:
			if is_local:
				sprite.modulate = Color(0.95, 1.0, 0.95, 1.0)
			else:
				sprite.modulate = Color(0.75, 0.9, 1.0, 1.0)

	if character.has_node("AnimationTree"):
		var anim_tree = character.get_node("AnimationTree")
		if anim_tree is AnimationTree:
			anim_tree.active = true

	return character

func _get_authority_session_id() -> String:
	var ids: Array = [local_session_id]
	for peer_id in peer_session_ids.keys():
		ids.append(peer_id)
	ids.sort()
	if ids.is_empty():
		return local_session_id
	return str(ids[0])

func _is_enemy_authority() -> bool:
	return not local_session_id.is_empty() and _get_authority_session_id() == local_session_id

func _update_local_hp_from_character() -> void:
	if !is_instance_valid(local_character):
		local_hp_current = -1
		local_hp_max = -1
		return

	var current_hp = local_character.get("current_hp")
	if typeof(current_hp) in [TYPE_INT, TYPE_FLOAT]:
		local_hp_current = int(current_hp)
	else:
		local_hp_current = -1

	var max_hp = local_character.get("max_hp")
	if typeof(max_hp) in [TYPE_INT, TYPE_FLOAT]:
		local_hp_max = int(max_hp)
	else:
		local_hp_max = -1

func _update_hp_hud() -> void:
	if !is_instance_valid(players_hp_label):
		return

	var lines: Array[String] = []
	lines.append("You: %s" % _format_hp(local_hp_current, local_hp_max))
	if !in_match:
		lines.append("Match: Offline")
		players_hp_label.text = "\n".join(lines)
		return

	var ids: Array = peer_session_ids.keys()
	ids.sort()
	for sid_variant in ids:
		var sid := str(sid_variant)
		var tag := sid.substr(0, min(8, sid.length()))
		if peer_hp.has(sid):
			var hp_entry: Dictionary = peer_hp[sid]
			lines.append("Peer %s: %s" % [tag, _format_hp(int(hp_entry.get("hp", -1)), int(hp_entry.get("hpm", -1)))])
		else:
			lines.append("Peer %s: --" % tag)

	players_hp_label.text = "\n".join(lines)

func _format_hp(current_hp: int, max_hp: int) -> String:
	if current_hp < 0 or max_hp <= 0:
		return "--"
	return "%d/%d" % [current_hp, max_hp]
