extends Node2D

## StrikerBulletHit — plays hit animation once then frees itself.

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D


func _ready() -> void:
	animated_sprite.animation_finished.connect(_on_animation_finished)
	animated_sprite.play("default")


func _on_animation_finished() -> void:
	queue_free()
