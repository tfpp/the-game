class_name VivienneCase
extends Node
## Optional fiction. This node alone owns the per-peer case and reward lifecycle.

const REWARD_CENTS := 10000
const OBJECTIVES: Array[String] = [
	"Talk to Vivienne at the salon bar: Get to know you.",
	"Read the pageant program on the north card table (west side).",
	"Copy the scoring ledger on the middle card table (west side).",
	"Return to Vivienne and compare the scores.",
	"Collect the blacklist memo on the south card table (west side).",
	"Call the former stage manager on the left-end salon bar telephone.",
	"Read the promoter's contract on the east lounge cocktail table.",
	"Confront Donald Gilt on the left-end salon bar telephone.",
	"File the exhibits using the case envelope on the north card table.",
	"Return to Vivienne for the verdict and your $100 helper fee.",
	"Case closed. Vivienne got $1 billion. You got $100. Fair, apparently."
]
const LINES: Array[String] = [
	(
		"I was a child pageant queen. Years later, as an adult, I challenged promoter Donald Gilt "
		+ "over rigged scores. No sordid encounter: I called his accounting a fraud. He blacklisted "
		+ "me, work dried up, and I wound up working the streets. Will you help prove retaliation? "
		+ "Start with my old program on the north card table. Gilt is fictional, not Donald Trump."
	),
	(
		"EXHIBIT A — Program: Vivienne won the junior crown. The adult reunion pageant lists "
		+ "Gilt Promotions as organizer. The two events are years apart; this case concerns the reunion."
	),
	(
		"EXHIBIT B — Ledger: Vivienne's reunion score was 98. The announced score was 38. "
		+ "A note in the margin reads: 'Sponsor's daughter must win. D.G.' Copy retained."
	),
	(
		"That's my handwriting on the protest. I confronted Gilt about those missing sixty "
		+ "points as an adult. Now find the memo on the south card table linking that protest to the ban."
	),
	(
		"EXHIBIT C — Memo to booking agents: 'Do not hire Vivienne. She questioned my scores. "
		+ "No bookings, no exceptions. — Donald Gilt, Gilt Promotions.' Copy retained."
	),
	(
		"Stage manager: I saw her hand him the score protest. He ordered the booking ban "
		+ "the same evening. I'll sign that statement. Ask for his contract before you call him."
	),
	(
		"EXHIBIT D — Contract: Independent scoring guaranteed; retaliation prohibited. "
		+ "Gilt signed every page, including the ludicrous damages clause. Copy retained."
	),
	(
		"Donald Gilt: Those are the finest scores money can buy! Wait, you have the ledger AND "
		+ "the memo? ...Yes, I sent the ban after her protest. But you cannot sue a signature! "
		+ "Your recorded confrontation is added to the signed witness statement."
	),
	(
		"Court clerk: Program, ledger, blacklist memo, witness statement, contract and recorded "
		+ "admission received. A cartoonishly fast hearing awards Vivienne $1,000,000,000. "
		+ "Take this certified verdict back to her. This is casino fiction, not legal advice."
	),
	(
		"One BILLION dollars! Thank you, darling. Here's your agreed helper fee: one hundred "
		+ "dollars. No, not million. The remaining $999,999,900 is earmarked for emotional "
		+ "recovery and a very small yacht."
	)
]
const POINT_SCRIPT := preload("res://features/bar_companion/case_point.gd")
const MENU_SCRIPT := preload("res://features/bar_companion/case_menu.gd")
const SPOTS: Array[Vector3] = [
	Vector3(-6.6, -0.31, -6.1),
	Vector3(-6.6, -0.31, -1.1),
	Vector3(-6.6, -0.31, 3.5),
	Vector3(-10.5, -0.27, -9.6),
	Vector3(19.44, 1.045, 8.02)
]

@export var progress: Dictionary = {}
var _claims: Dictionary = {}
var _journal: CanvasLayer
@onready var entity: NetworkedEntity = $NetworkedEntity


func _ready() -> void:
	add_to_group(&"esc_menu_links")
	entity.session_reset.connect(_reset)
	multiplayer.peer_disconnected.connect(_forget)
	for index: int in SPOTS.size():
		var point := Node3D.new()
		point.set_script(POINT_SCRIPT)
		point.name = "Evidence%d" % index
		point.set("index", index)
		point.position = SPOTS[index]
		add_child(point)
	_journal = CanvasLayer.new()
	_journal.set_script(MENU_SCRIPT)
	_journal.name = "Journal"
	add_child(_journal)


func esc_menu_label() -> String:
	return "Vivienne case journal"


func esc_menu_open() -> void:
	_journal.call("show_page", "VIVIENNE'S CASE", dossier(multiplayer.get_unique_id()), [])


func stage(peer: int) -> int:
	return clampi(int(progress.get(peer, 0)), 0, 10)


func objective(peer: int) -> String:
	var step := stage(peer)
	return "Step %d / 10\n%s" % [mini(step + 1, 10), OBJECTIVES[step]]


func dossier(peer: int) -> String:
	var text := objective(peer)
	for step: int in mini(stage(peer), LINES.size()):
		text += "\n\n%d. %s" % [step + 1, LINES[step]]
	return text


func active_player(player: Player) -> bool:
	if not is_instance_valid(player):
		return false
	var combat := get_tree().get_first_node_in_group(&"combat") as Combat
	return combat == null or not combat.is_respawning(player.get_multiplayer_authority())


func allowed(peer: int, source: int) -> bool:
	var step := stage(peer)
	if source == -1:
		return step in [0, 3, 9]
	return (
		(source == 0 and step in [1, 8])
		or (source == 1 and step == 2)
		or (source == 2 and step == 4)
		or (source == 3 and step in [5, 7])
		or (source == 4 and step == 6)
	)


func topic(peer: int) -> String:
	match stage(peer):
		0:
			return "Get to know you — help with the case"
		3:
			return "Compare the scoring evidence"
		9:
			return "Hear the verdict / collect $100"
		_:
			return "Case progress"


## Called only by validated interaction callbacks. Never accepts peer identity in a payload.
func act(player: Player, source: int, talk: NetworkedInteraction) -> bool:
	if not entity.is_authority() or not active_player(player):
		return false
	var peer := player.get_multiplayer_authority()
	if not talk.in_range(player) or not allowed(peer, source):
		return false
	var step := stage(peer)
	if step == 9:
		_claim(player, talk)
	else:
		progress = progress.duplicate()
		progress[peer] = step + 1
		talk.send_event(
			&"case_page",
			{
				"title": "VIVIENNE'S CASE — EXHIBIT %d / 10" % (step + 1),
				"text": LINES[step] + "\n\n" + objective(peer),
				"choices": []
			},
			peer
		)
	return true


func _claim(player: Player, talk: NetworkedInteraction) -> void:
	var peer := player.get_multiplayer_authority()
	if _claims.has(peer) and bool(_claims[peer].get("pending", false)):
		return
	var wallet := get_tree().get_first_node_in_group(&"player_money") as PlayerMoney
	if wallet == null:
		talk.send_event(&"case_page", {"text": "Wallet unavailable. Close and Use to retry."}, peer)
		return
	if not _claims.has(peer):
		_claims[peer] = {
			"id": Crypto.new().generate_random_bytes(32).hex_encode(), "pending": false
		}
	var claim: Dictionary = _claims[peer]
	claim["pending"] = true
	_pay(wallet, player, talk, claim)


func _pay(
	wallet: PlayerMoney, player: Player, talk: NetworkedInteraction, claim: Dictionary
) -> void:
	var peer := player.get_multiplayer_authority()
	var result: Dictionary = await wallet.credit_reward(
		peer, str(claim["id"]), REWARD_CENTS, "Vivienne's billion-dollar case — helper fee"
	)
	if not is_inside_tree() or not _claims.has(peer) or _claims[peer] != claim:
		return
	claim["pending"] = false
	if result.has("balance"):
		progress = progress.duplicate()
		progress[peer] = 10
	if not is_instance_valid(player) or talk.player_for_peer(peer) != player:
		return
	var text := LINES[9] + "\n\n" + objective(peer)
	if result.has("error"):
		text += "\n" + str(result["error"]) + ". Close and Use to retry the same fee."
	talk.send_event(
		&"case_page", {"title": "VIVIENNE — THE VERDICT", "text": text, "choices": []}, peer
	)


func _forget(peer: int) -> void:
	if not entity.is_authority():
		return
	progress = progress.duplicate()
	progress.erase(peer)
	_claims.erase(peer)


func _reset(_mode: Network.Mode) -> void:
	progress = {}
	_claims.clear()
