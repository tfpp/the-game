class_name MetroResidents
extends Node3D
## Non-interactive sheltering residents: presentation sampled from the metro's
## authoritative clock, not independently simulated NPCs or a second spawn system.

const BENCHES: Array[float] = [-42.0, -30.0, 30.0, 42.0]
const ACTIVE_DISTANCE := 28.0
var zone: MetroZone
var models: Array[PatronModel] = []
var starts: Array[Vector3] = []
var ends: Array[Vector3] = []
var sleeping: Array[bool] = []
var headings: Array[float] = []
## Appearance and walk phase; equal for the same person on every platform.
var looks: Array[int] = []


func _ready() -> void:
	for car: int in 5:
		var center := MetroRules.car_center(car)
		for bay: float in [-5.0, 5.0]:
			_add(Vector3(-1, 1.2, center + bay + 0.37), Vector3.ZERO, true, -PI / 2)
		_add(Vector3(0, 1.2, center - 8.8), Vector3(0, 1.2, center - 6.3), false, 0)
	var first := models.size()
	if zone.station_index >= 0:
		_add_platform(self, first)
	elif zone.scenery != null:
		# Riders see the same people on the platforms they pull out of and into.
		for copy: String in ["Departure", "Arrival"]:
			_add_platform(zone.scenery.get_node(copy) as Node3D, first)
	update_view(0.0, true)


func _add_platform(parent: Node3D, look: int) -> void:
	for z: float in BENCHES:
		_add(Vector3(11, 1.2, z), Vector3.ZERO, true, PI / 2, parent, look)
		look += 1
	for z: float in [-18.0, 6.0, 48.0]:
		_add(Vector3(9, 1.2, z), Vector3(9, 1.2, z + 6), false, 0, parent, look)
		look += 1


func _add(
	start: Vector3, end: Vector3, asleep: bool, yaw: float, parent: Node3D = null, look := -1
) -> void:
	var model := PatronModel.new()
	model.name = "Resident%d" % models.size()
	(parent if parent != null else self).add_child(model)
	var index := models.size() if look < 0 else look
	# Unnamed ordinary residents, not the casino's named patron looks.
	(
		model
		. dress_up(
			{
				"skin": posmod(index * 3, PlayerSkin.TONES.size()),
				"hair": "long" if index % 3 == 0 else "crop",
				"hair_color": index % 2,
				"shirt": [9, 1, 6][index % 3],
				"pants": [1, 9][index % 2],
				"tie": -1,
				"girl": index % 3 == 0,
			}
		)
	)
	models.append(model)
	starts.append(start)
	ends.append(end)
	sleeping.append(asleep)
	headings.append(yaw)
	looks.append(index)


## A bounded out-and-back walk with four seconds resting at each end.
## Every peer (including a newly loaded room) samples the same server-owned phase.
static func stroll(start: Vector3, end: Vector3, clock: float) -> Dictionary:
	var phase := fposmod(clock, 20.0)
	var returning := phase >= 10
	var amount := clampf((phase - (10.0 if returning else 0.0) - 4) / 6, 0, 1)
	var direction := (start - end) if returning else (end - start)
	return {
		"position": end.lerp(start, amount) if returning else start.lerp(end, amount),
		"yaw": atan2(-direction.x, -direction.z),
		"walk": 0.0 if amount == 0 or amount == 1 else 0.5,
	}


func _process(delta: float) -> void:
	update_view(delta)


func update_view(delta: float, force := false) -> void:
	var metro := zone.service()
	var clock := metro.net_cycle * MetroRules.PERIOD + metro.display_time()
	var local := metro.player(multiplayer.get_unique_id())
	for index: int in models.size():
		var model := models[index]
		var point := starts[index]
		var yaw := headings[index]
		var walk := 0.0
		if not sleeping[index]:
			var sample := stroll(starts[index], ends[index], clock + looks[index] * 2.7)
			point = sample["position"]
			yaw = sample["yaw"]
			walk = sample["walk"]
		if point.x < 2:
			# Station presentation accelerates with its train; ride compartments stay fixed.
			point.z += zone.train.position.z
		model.position = point
		model.rotation.y = yaw
		model.visible = zone.train.visible if point.x < 2 else true
		var nearby := (
			local != null
			and local.global_position.distance_to(model.global_position) < ACTIVE_DISTANCE
		)
		if not force and not nearby:
			continue
		if sleeping[index]:
			# Hip on the existing cushion; a relaxed forward slump, not a dead ragdoll.
			var hip := 0.48 if point.x < 2 else 0.5
			model.sit(delta, hip, 0, 0.12, -0.65)
			model.avatar._torso.rotation.x = -0.3
			model.avatar._head.rotation.x = -0.8
			model.avatar.human.pose(model.avatar, false, false)
		else:
			model.pose(delta, walk, 0, 0, clock)
