extends RefCounted
## Literal resource paths keep the reusable kit visible to the export scanner.

const PROPS := {
	"street_lamp": preload("res://features/street_props/props/street_lamp.tscn"),
	"wall_lamp": preload("res://features/street_props/props/wall_lamp.tscn"),
	"traffic_cone": preload("res://features/street_props/props/traffic_cone.tscn"),
	"construction_barricade":
	preload("res://features/street_props/props/construction_barricade.tscn"),
	"concrete_barrier": preload("res://features/street_props/props/concrete_barrier.tscn"),
	"chain_link_fence": preload("res://features/street_props/props/chain_link_fence.tscn"),
	"dumpster": preload("res://features/street_props/props/dumpster.tscn"),
	"garbage_bag": preload("res://features/street_props/props/garbage_bag.tscn"),
	"wooden_crate": preload("res://features/street_props/props/wooden_crate.tscn"),
	"steel_barrel": preload("res://features/street_props/props/steel_barrel.tscn"),
	"electrical_cabinet": preload("res://features/street_props/props/electrical_cabinet.tscn"),
	"bus_shelter": preload("res://features/street_props/props/bus_shelter.tscn"),
	"street_bench": preload("res://features/street_props/props/street_bench.tscn"),
	"street_trash_can": preload("res://features/street_props/props/street_trash_can.tscn"),
	"fire_hydrant": preload("res://features/street_props/props/fire_hydrant.tscn"),
	"phone_booth": preload("res://features/street_props/props/phone_booth.tscn"),
	"newspaper_box": preload("res://features/street_props/props/newspaper_box.tscn"),
	"parking_meter": preload("res://features/street_props/props/parking_meter.tscn"),
	"service_door": preload("res://features/street_props/props/service_door.tscn"),
	"rolling_shutter": preload("res://features/street_props/props/rolling_shutter.tscn"),
	"fire_escape_platform": preload("res://features/street_props/props/fire_escape_platform.tscn"),
	"air_conditioner": preload("res://features/street_props/props/air_conditioner.tscn")
}
const BUILDINGS := [
	preload("res://features/street_district/props/brick_tenement.tscn"),
	preload("res://features/street_district/props/corner_store.tscn"),
	preload("res://features/street_district/props/plaster_apartments.tscn"),
	preload("res://features/street_district/props/shutter_warehouse.tscn"),
	preload("res://features/street_district/props/narrow_office.tscn"),
	preload("res://features/street_district/props/laundry_block.tscn"),
	preload("res://features/street_district/props/service_workshop.tscn"),
	preload("res://features/street_district/props/hotel_facade.tscn"),
	preload("res://features/street_district/props/concrete_commercial.tscn"),
	preload("res://features/street_district/props/brick_storeroom.tscn")
]


static func prop(parent: Node3D, id: String, at: Vector3, yaw: float = 0) -> Node3D:
	var packed: PackedScene = PROPS[id]
	var node := packed.instantiate() as Node3D
	parent.add_child(node)
	node.position = at
	node.rotation.y = yaw
	return node
