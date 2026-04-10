extends RefCounted

func capture_enemy_states(world_root: Node) -> Array:
	var enemies := world_root.get_tree().get_nodes_in_group("enemies")
	var payload: Array = []
	for enemy in enemies:
		if not is_instance_valid(enemy):
			continue
		if not (enemy is Node2D):
			continue
		if world_root != null and not world_root.is_ancestor_of(enemy):
			continue

		var node := enemy as Node2D
		var entry := {
			"path": str(world_root.get_path_to(node)),
			"x": node.global_position.x,
			"y": node.global_position.y,
			"sx": node.scale.x,
			"sy": node.scale.y
		}

		var sprite := node.get_node_or_null("Sprite2D")
		if sprite is Sprite2D:
			entry["fh"] = sprite.flip_h

		var animated := node.get_node_or_null("AnimatedSprite2D")
		if animated is AnimatedSprite2D:
			entry["aa"] = str(animated.animation)
			entry["af"] = animated.frame
			entry["afh"] = animated.flip_h

		var anim_player := node.get_node_or_null("AnimationPlayer")
		if anim_player is AnimationPlayer:
			entry["ap"] = str(anim_player.current_animation)

		payload.append(entry)

	return payload

func apply_enemy_states(world_root: Node, states: Array) -> void:
	for item in states:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		if not item.has("path"):
			continue

		var node = world_root.get_node_or_null(NodePath(str(item["path"])))
		if not (node is Node2D):
			continue

		var enemy := node as Node2D
		if item.has("x") and item.has("y"):
			enemy.global_position = Vector2(float(item["x"]), float(item["y"]))
		if item.has("sx") and item.has("sy"):
			enemy.scale = Vector2(float(item["sx"]), float(item["sy"]))

		var sprite := enemy.get_node_or_null("Sprite2D")
		if sprite is Sprite2D and item.has("fh"):
			sprite.flip_h = bool(item["fh"])

		var animated := enemy.get_node_or_null("AnimatedSprite2D")
		if animated is AnimatedSprite2D:
			if item.has("aa"):
				var anim_name := StringName(str(item["aa"]))
				if animated.animation != anim_name:
					animated.play(anim_name)
			if item.has("af"):
				animated.frame = int(item["af"])
			if item.has("afh"):
				animated.flip_h = bool(item["afh"])

		var anim_player := enemy.get_node_or_null("AnimationPlayer")
		if anim_player is AnimationPlayer and item.has("ap"):
			var target_anim := str(item["ap"])
			if not target_anim.is_empty() and anim_player.current_animation != target_anim:
				anim_player.play(target_anim)
