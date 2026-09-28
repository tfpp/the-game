extends GutTest
## Server-authoritative health and kills (features/combat/combat.gd). Runs
## single-process like test_holdables.gd, so peer 1 is the server and RPCs resolve
## locally (see slot_machine's `interaction.use()` test for the same trick applied
## to a real `.rpc_id()` call).

const CombatScene := preload("res://features/combat/feature.tscn")
const PlayerScene := preload("res://core/player/player.tscn")

var _combat: Combat


func before_each() -> void:
	_combat = CombatScene.instantiate() as Combat
	add_child_autofree(_combat)


func test_an_untouched_peer_starts_at_max_health() -> void:
	assert_eq(_combat.health_for(1), Combat.MAX_HEALTH)


func test_damage_below_max_health_just_reduces_it() -> void:
	_combat.apply_damage(1, 30.0, 2)
	assert_eq(_combat.health_for(1), Combat.MAX_HEALTH - 30.0)
	_combat.apply_damage(1, 20.0, 2)
	assert_eq(_combat.health_for(1), Combat.MAX_HEALTH - 50.0)


func test_zero_or_negative_damage_does_nothing() -> void:
	_combat.apply_damage(1, 0.0, 2)
	_combat.apply_damage(1, -5.0, 2)
	assert_eq(_combat.health_for(1), Combat.MAX_HEALTH)


func test_lethal_damage_heals_the_victim_back_to_max() -> void:
	_combat.apply_damage(1, Combat.MAX_HEALTH, 2)
	assert_eq(_combat.health_for(1), Combat.MAX_HEALTH)


func test_lethal_damage_announces_the_kill() -> void:
	var deaths: Array = []
	_combat.player_died.connect(
		func(victim: int, attacker: int) -> void: deaths.append([victim, attacker])
	)
	_combat.apply_damage(1, Combat.MAX_HEALTH, 2)
	assert_eq(deaths, [[1, 2]])


func test_lethal_damage_teleports_the_victim_near_the_respawn_point() -> void:
	var player := PlayerScene.instantiate() as Player
	player.name = "1"
	player.set_multiplayer_authority(1)
	add_child_autofree(player)
	await get_tree().physics_frame
	_combat.apply_damage(1, Combat.MAX_HEALTH, 2)
	var offset := player.global_position - Combat.RESPAWN_POINT
	offset.y = 0.0
	assert_lt(offset.length(), Combat.RESPAWN_JITTER * 1.5)


func test_keeps_separate_health_per_peer() -> void:
	_combat.apply_damage(1, 40.0, 2)
	assert_eq(_combat.health_for(2), Combat.MAX_HEALTH)
