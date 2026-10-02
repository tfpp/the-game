extends Node3D

const LAYOUT := preload("res://features/street_district/layout.gd")


func _ready() -> void:
	LAYOUT.build(self)
