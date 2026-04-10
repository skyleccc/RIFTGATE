extends RefCounted

func capture_local_state(local_character: Node2D) -> Dictionary:
	var payload := {
		"x": local_character.global_position.x,
		"y": local_character.global_position.y,
		"fh": false,
		"anim": "",
		"blend": 0.0,
		"hp": -1,
		"hpm": -1
	}

	var sprite := local_character.get_node_or_null("Player")
	if sprite is Sprite2D:
		payload["fh"] = sprite.flip_h

	var animation_tree := local_character.get_node_or_null("AnimationTree")
	if animation_tree is AnimationTree:
		var playback = animation_tree.get("parameters/playback")
		if playback and playback.has_method("get_current_node"):
			payload["anim"] = str(playback.get_current_node())
		var blend = animation_tree.get("parameters/Move/blend_position")
		if typeof(blend) in [TYPE_FLOAT, TYPE_INT]:
			payload["blend"] = float(blend)

	var current_hp = local_character.get("current_hp")
	if typeof(current_hp) in [TYPE_INT, TYPE_FLOAT]:
		payload["hp"] = int(current_hp)

	var max_hp = local_character.get("max_hp")
	if typeof(max_hp) in [TYPE_INT, TYPE_FLOAT]:
		payload["hpm"] = int(max_hp)

	return payload

func apply_remote_state(remote_character: Node2D, state: Dictionary) -> void:
	if state.has("x") and state.has("y"):
		remote_character.global_position = Vector2(float(state["x"]), float(state["y"]))

	var sprite := remote_character.get_node_or_null("Player")
	if sprite is Sprite2D and state.has("fh"):
		sprite.flip_h = bool(state["fh"])

	var animation_tree := remote_character.get_node_or_null("AnimationTree")
	if animation_tree is AnimationTree:
		var playback = animation_tree.get("parameters/playback")
		if playback and playback.has_method("travel") and state.has("anim"):
			var anim_name := str(state["anim"])
			if not anim_name.is_empty() and playback.has_method("get_current_node"):
				if str(playback.get_current_node()) != anim_name:
					playback.travel(anim_name)
		if state.has("blend"):
			animation_tree.set("parameters/Move/blend_position", float(state["blend"]))
