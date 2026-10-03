class_name Trump
extends CasinoPatron
## A patron who follows the mayor instead of walking an independent route.
## Bribing him costs more each time and tilts your slot machine odds slightly.

const PRICE_CENTS := 10000
## Bribes that still add favor; the price doubles with each one.
const MAX_BRIBES := 5
## Chance per bribe that a losing slot spin gets one more roll of the reels.
const FAVOR_PER_BRIBE := 0.2
const FOLLOW_DISTANCE := 1.5
const FOLLOW_SPEED := 1.8
## Trump pats Mitch McConnell on the head when they come this close.
const PAT_RANGE := 0.9
const PAT_COOLDOWN_S := 15.0
const PAT_HOLD_S := 2.0
const PAT_LINE := "Good boy."
## Players within this distance also get the line as a subtitle.
const PAT_HEARING_M := 10.0

var _leader: CasinoPatron
var _mitch: CasinoPatron
var _pat_cooldown := 0.0
var _patting := 0.0
var _bubble: Label3D
var _charging: Dictionary[int, bool] = {}
## Server: peer id -> accepted bribes. Session-only, forgotten on disconnect.
var _bribes: Dictionary[int, int] = {}
## Client copy of this peer's own bribe count, for the prompt's price.
var _my_bribes := 0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	super._ready()
	_setup_talk()
	add_to_group(&"trump_favor")
	_talk.event_received.connect(_on_bribe_event)
	multiplayer.peer_disconnected.connect(func(peer: int) -> void: _bribes.erase(peer))
	_talk.session_reset.connect(func(_mode: Network.Mode) -> void: _bribes.clear())
	_bubble = Label3D.new()
	_bubble.name = "SpeechBubble"
	_bubble.text = PAT_LINE
	_bubble.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_bubble.font_size = 48
	_bubble.outline_size = 12
	_bubble.pixel_size = 0.004
	_bubble.modulate = Color(1, 0.85, 0.4)
	_bubble.position = Vector3(0, 2.35, 0)
	_bubble.visible = false
	add_child(_bubble)


## Cost of a peer's next bribe: $100, $200, $400, $800, $1,600.
static func bribe_price(bribes: int) -> int:
	return PRICE_CENTS << clampi(bribes, 0, MAX_BRIBES - 1)


## Chance that a spin gets Trump's extra roll after `bribes` bribes.
static func favor_chance(bribes: int) -> float:
	return clampf(bribes * FAVOR_PER_BRIBE, 0.0, 1.0)


func bribes_for(peer: int) -> int:
	return int(_bribes.get(peer, 0))


## Server-only: extra slot rerolls (0 or 1) granted by this peer's bribes.
func favor_rerolls(peer: int) -> int:
	return 1 if _rng.randf() < favor_chance(bribes_for(peer)) else 0


## True when Trump at `from` is close enough to pat a head at `to`.
static func can_pat(from: Vector3, to: Vector3) -> bool:
	return Vector2(to.x - from.x, to.z - from.z).length() <= PAT_RANGE


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if multiplayer.is_server():
		_pat_cooldown = maxf(_pat_cooldown - delta, 0.0)
		_try_pat()


## Server-only: pats Mitch McConnell when both are up and close together.
func _try_pat() -> void:
	if _pat_cooldown > 0.0 or not net_alive or net_ragdoll:
		return
	if not is_instance_valid(_mitch):
		for node: Node in get_parent().get_children():
			if node is Mitch:
				_mitch = node as Mitch
				break
	if not is_instance_valid(_mitch) or not _mitch.net_alive or _mitch.net_ragdoll:
		return
	if not can_pat(global_position, _mitch.global_position):
		return
	_pat_cooldown = PAT_COOLDOWN_S
	_stagger = PAT_HOLD_S
	(_mitch as Mitch).hold(PAT_HOLD_S)
	net_yaw = PatronMath.facing_yaw(_mitch.global_position - global_position)
	_pat_head.rpc()


func _process(delta: float) -> void:
	super._process(delta)
	_patting = maxf(_patting - delta, 0.0)
	_bubble.visible = _patting > 0.0 and net_alive
	if AnimationBisect.patrons:
		_body.reach(clampf(_patting * 2.0, 0.0, 1.0) * (0.8 + 0.2 * sin(_patting * 18.0)))


func is_patting() -> bool:
	return _patting > 0.0


@rpc("authority", "call_local", "reliable")
func _pat_head() -> void:
	_patting = PAT_HOLD_S
	for node: Node in get_tree().get_nodes_in_group(&"players"):
		var player := node as Node3D
		if player == null or player.get_multiplayer_authority() != multiplayer.get_unique_id():
			continue
		if player.global_position.distance_to(global_position) <= PAT_HEARING_M:
			Subtitles.say(get_tree(), speaker_name(), PAT_LINE)
		return


func _walk_on(delta: float) -> void:
	if not is_instance_valid(_leader):
		for node: Node in get_parent().get_children():
			if node is CasinoPatron and node.look == PatronModel.MAMDANI_LOOK:
				_leader = node as CasinoPatron
				break
	if not is_instance_valid(_leader) or not _leader.net_alive:
		return
	var offset := _leader.global_position - global_position
	offset.y = 0.0
	var distance := offset.length()
	if distance <= FOLLOW_DISTANCE:
		return
	var heading := offset / distance
	net_yaw = PatronMath.facing_yaw(heading)
	if not _player_in_the_way(heading):
		_waited = 0.0
	elif _waited < PatronMath.MAX_WAIT_S:
		_waited += delta
		return
	# Collide with world geometry if either patron was knocked off the clear aisle.
	move_and_collide(heading * minf(FOLLOW_SPEED * delta, distance - FOLLOW_DISTANCE))
	_return_to = null


func can_use(player: Player) -> bool:
	return net_alive and not net_ragdoll and _talk != null and _talk.in_range(player)


func interaction_text() -> String:
	if _my_bribes >= MAX_BRIBES:
		return "Talk to Donald Trump (he's already yours)"
	return "Bribe Donald Trump (-%s)" % PlayerMoney.format_money(bribe_price(_my_bribes))


func speaker_name() -> String:
	return "Donald Trump"


func _apply_talk(player: Player) -> bool:
	var peer := player.get_multiplayer_authority()
	if _charging.has(peer):
		return false
	if bribes_for(peer) >= MAX_BRIBES:
		_say(peer, "You've bought all the favor there is. Tremendous.")
		return true
	var wallet := get_tree().get_first_node_in_group(&"player_money") as PlayerMoney
	if wallet == null:
		_say(peer, "Wallet unavailable. Try again later.")
		return false
	_charging[peer] = true
	# Launch asynchronous wallet work without yielding the validated apply callback.
	_charge(wallet, peer, player)
	return true


func _charge(wallet: PlayerMoney, peer: int, player: Player) -> void:
	var id := Crypto.new().generate_random_bytes(32).hex_encode()
	var price := bribe_price(bribes_for(peer))
	var result: Dictionary = await wallet.charge(peer, id, price)
	_charging.erase(peer)
	# Never deliver a delayed reply to a disconnected/replaced player's peer ID.
	if peer != multiplayer.get_unique_id() and not multiplayer.get_peers().has(peer):
		return
	if not result.has("error"):
		_bribes[peer] = bribes_for(peer) + 1
		_talk.send_event(&"bribes", {"count": bribes_for(peer)}, peer)
	if not is_instance_valid(player) or _talk.player_for_peer(peer) != player:
		return
	if result.has("error"):
		_say(peer, str(result["error"]))
	else:
		_say(peer, TrumpQuips.pick(_rng))


func _on_bribe_event(event: StringName, payload: Dictionary) -> void:
	if event == &"bribes":
		_my_bribes = clampi(int(payload.get("count", 0)), 0, MAX_BRIBES)
