extends RefCounted

const BLUE_PORTAL_SCENE := preload("res://portal/PortalBlue.tscn")
const ORANGE_PORTAL_SCENE := preload("res://portal/PortalOrange.tscn")

func capture_local_portal_state(local_character: Node2D) -> Dictionary:
	var payload := {
		"b": {},
		"o": {}
	}

	var portal_gun := local_character.get_node_or_null("PortalGun")
	if portal_gun == null:
		return payload

	var blue_portal = portal_gun.get("active_blue_portal")
	var orange_portal = portal_gun.get("active_orange_portal")

	payload["b"] = _portal_to_dict(blue_portal)
	payload["o"] = _portal_to_dict(orange_portal)
	return payload

func apply_remote_portals(
	session_id: String,
	world_root: Node2D,
	state: Dictionary,
	remote_portals: Dictionary
) -> void:
	if not remote_portals.has(session_id):
		remote_portals[session_id] = {
			"b": null,
			"o": null
		}

	var entry: Dictionary = remote_portals[session_id]
	entry["b"] = _apply_one_portal(world_root, entry.get("b"), state.get("b", {}), true, session_id)
	entry["o"] = _apply_one_portal(world_root, entry.get("o"), state.get("o", {}), false, session_id)
	remote_portals[session_id] = entry

func clear_remote_portals_for(session_id: String, remote_portals: Dictionary) -> void:
	if not remote_portals.has(session_id):
		return
	var entry: Dictionary = remote_portals[session_id]
	for key in ["b", "o"]:
		var node = entry.get(key)
		if node != null and is_instance_valid(node):
			node.queue_free()
	remote_portals.erase(session_id)

func clear_all_remote_portals(remote_portals: Dictionary) -> void:
	for session_id in remote_portals.keys():
		clear_remote_portals_for(session_id, remote_portals)

func _portal_to_dict(portal: Variant) -> Dictionary:
	if portal == null or not is_instance_valid(portal):
		return {}
	if not (portal is Node2D):
		return {}
	var node := portal as Node2D
	return {
		"x": node.global_position.x,
		"y": node.global_position.y,
		"r": node.global_rotation
	}

func _apply_one_portal(
	world_root: Node2D,
	existing: Variant,
	portal_data: Variant,
	is_blue: bool,
	session_id: String
):
	if typeof(portal_data) != TYPE_DICTIONARY or (portal_data as Dictionary).is_empty():
		if existing != null and is_instance_valid(existing):
			existing.queue_free()
		return null

	var node = existing
	if node == null or not is_instance_valid(node):
		node = (BLUE_PORTAL_SCENE if is_blue else ORANGE_PORTAL_SCENE).instantiate()
		node.name = "%sRemotePortal_%s" % ["Blue" if is_blue else "Orange", session_id]
		world_root.add_child(node)
		_prepare_remote_portal_visual(node)

	var dict_data := portal_data as Dictionary
	if dict_data.has("x") and dict_data.has("y"):
		node.global_position = Vector2(float(dict_data["x"]), float(dict_data["y"]))
	if dict_data.has("r"):
		node.global_rotation = float(dict_data["r"])
	return node

func _prepare_remote_portal_visual(node: Node) -> void:
	if node.has_method("set_script"):
		node.set_script(null)
	if node is Area2D:
		var area := node as Area2D
		area.collision_layer = 0
		area.collision_mask = 0
		area.monitoring = false
		area.monitorable = false
		area.set_physics_process(false)
		node.add_to_group("remote_portals")
