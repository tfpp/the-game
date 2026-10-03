extends Node3D
## Two cosmetic avatars, reconstructed from the replicated book (including late joins).
## No local simulation: only the server's chosen attacker lunges and the loser falls.

var _birds: Array[Node3D] = []
var _labels: Array[Label3D] = []
var _round := -1
var _age := 0.0

@onready var book: ChickenBettingBook = get_parent() as ChickenBettingBook


func _process(delta: float) -> void:
	if DisplayServer.get_name() == "headless":
		return
	visible = book.room.is_loaded()
	if not visible:
		return
	if book.state["birds"].is_empty():
		for bird: Node3D in _birds:
			bird.queue_free()
		_birds.clear()
		_labels.clear()
		return
	if _birds.is_empty():
		for index: int in 2:
			var bird := ChickenAvatar.new()
			add_child(bird)
			_birds.append(bird)
			var label := Label3D.new()
			label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			label.font_size = 32
			label.pixel_size = 0.003
			add_child(label)
			_labels.append(label)
	if _round != int(book.state["round"]):
		_round = int(book.state["round"])
		_age = 0.0
	_age += delta
	var wave := sin(clampf(_age / book.config.round_seconds, 0.0, 1.0) * PI)
	for index: int in 2:
		var side := -1.0 if index == 0 else 1.0
		var attacking: bool = (
			not book.state["attack"].is_empty() and (int(book.state["attack"]["attacker"]) == index)
		)
		var knocked_out := int(book.state["health"][index]) == 0
		var bird := _birds[index]
		bird.position = Vector3(side * 1.5, 0, -1)
		bird.rotation = Vector3(0, side * PI / 2.0, 0)
		if _round > 0:
			bird.position.x -= side * wave * (1.85 if attacking else -0.18)
			bird.position.y = wave * (0.18 if attacking else 0.06)
			bird.rotation.x = wave * (-0.45 if attacking else 0.25)
		if knocked_out:
			bird.rotation.z = side * PI / 2.0
			bird.position.y = 0.3
		_labels[index].position = Vector3(side * 1.8, 1.6, -1)
		_labels[index].text = (
			"%s\nHP %d · %.2f×%s"
			% [
				book.state["birds"][index]["name"],
				book.state["health"][index],
				book.state["odds"][index],
				" · KO" if knocked_out else ""
			]
		)
