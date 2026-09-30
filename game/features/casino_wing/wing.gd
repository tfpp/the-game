extends Node3D

const LAYOUT := preload("res://features/casino_wing/layout.gd")
@export var furnishing_seed := 1964


func _ready() -> void:
	LAYOUT.build(self, furnishing_seed)
