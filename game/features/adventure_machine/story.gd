extends RefCounted
## Original cabinet fiction. Only the cabinet's server creates/mutates a player's story.

const TITLE := "Brine & Bureaucracy"
const ROOMS := {
	"quay":
	{
		"title": "The Salt-Tax Quay",
		"text":
		(
			"Your hired boat cannot sail without its bell. Captain Quill has impounded it "
			+ "for 'excessive dinging'. A gull guards a shiny token. A horseshoe magnet lies "
			+ "beside a drain, where a small iron key glints just out of reach."
		)
	},
	"tavern":
	{
		"title": "The Uninsured Mermaid",
		"text":
		(
			"A tavern with no mermaids and very little insurance. A cracker sits on the "
			+ "counter. Retired pirate Auntie Wake practices devastating remarks into a teacup."
		)
	},
	"shop":
	{
		"title": "The Chandlery of Dubious Value",
		"text":
		(
			"The shopkeeper sells rope for one brass token. 'Guaranteed to be longer "
			+ "than it is wide.' A sign reads: COMBINE THINGS. BLAME YOURSELF."
		)
	},
	"fort":
	{
		"title": "Fort Fine Print",
		"text":
		(
			"Captain Quill, a ghost in a very solid uniform, guards the customs locker. "
			+ "'No bell leaves without my approval. Or a truly crushing comeback.' "
			+ "The locker has an iron lock."
		)
	}
}
const ITEMS := {
	"cracker": "Stale cracker",
	"token": "Brass token",
	"magnet": "Horseshoe magnet",
	"rope": "Dubious rope",
	"fishing": "Magnet on a rope",
	"key": "Iron locker key",
	"bell": "Ship's bell"
}
const INSULTS: Array[String] = [
	"My paperwork has sunk a thousand ships!",
	"You have the backbone of a damp receipt!",
	"I shall file you under insignificant!"
]
const RETORTS: Array[String] = [
	"Then your filing cabinet must be a reef.",
	"At least I am proof of a purchase.",
	"Good. I was worried you would misfile me."
]
# Rotate response positions; the right answer is not always the first button.
const RESPONSE_ORDER: Array[Array] = [[1, 0, 2], [2, 0, 1], [2, 1, 0]]
const INTRO := (
	"A fictional pirate adventure, installed by someone with a very long lunch break. "
	+ "Recover your ship's bell and escape the harbour. Choose verbs below; no typing, "
	+ "death traps or real-money prizes. Close anytime; Use the cabinet to continue."
)

var room := "quay"
var inventory: Array[String] = []
var fed_gull := false
var bought_rope := false
var learned := false
var gate_open := false
var won := false
var duel := -1
var confirming_restart := false
var revision := 0
var message := INTRO
var history: Array[String] = []


func choices() -> Array[Dictionary]:
	if confirming_restart:
		return [
			_choice("confirm_restart", "Start over — erase this adventure"),
			_choice("cancel_restart", "Keep my adventure")
		]
	if won:
		return [_choice("look", "Read the ending again"), _choice("restart", "Play again")]
	if duel >= 0:
		var result: Array[Dictionary] = []
		for index: int in RESPONSE_ORDER[duel]:
			result.append(_choice("retort_%d" % index, RETORTS[index]))
		result.append(_choice("retreat", "Back away with dignity (approximately)"))
		result.append(_choice("hint", "Hint"))
		return result
	var result: Array[Dictionary] = [_choice("look", "Look around")]
	match room:
		"quay":
			if not fed_gull:
				result.append(_choice("gull", "Talk to the gull"))
			if not _has("magnet") and not _has("fishing"):
				result.append(_choice("take_magnet", "Pick up horseshoe magnet"))
			if _has("cracker"):
				result.append(_choice("feed", "Use cracker on gull"))
			if _has("fishing") and not _has("key"):
				result.append(_choice("fish", "Use magnet on a rope in drain"))
			if _has("bell"):
				result.append(_choice("sail", "Use bell on your boat"))
			result.append(_choice("go_tavern", "Walk to tavern"))
			result.append(_choice("go_shop", "Walk to chandlery"))
			result.append(_choice("go_fort", "Walk to customs fort"))
		"tavern":
			if not _has("cracker") and not fed_gull:
				result.append(_choice("take_cracker", "Pick up stale cracker"))
			result.append(_choice("learn", "Talk to Auntie Wake about verbal duels"))
		"shop":
			result.append(_choice("merchant", "Talk to shopkeeper"))
			if _has("token") and not bought_rope:
				result.append(_choice("buy_rope", "Trade brass token for rope"))
		"fort":
			if not gate_open:
				result.append(_choice("challenge", "Challenge Captain Quill to a battle of wits"))
			else:
				result.append(_choice("captain", "Talk to the defeated captain"))
				if _has("key") and not _has("bell"):
					result.append(_choice("unlock", "Use iron key on customs locker"))
	if room != "quay":
		result.append(_choice("go_quay", "Walk back to quay"))
	if _has("rope") and _has("magnet"):
		result.append(_choice("combine", "Combine rope with horseshoe magnet"))
	result.append(_choice("hint", "Hint"))
	result.append(_choice("restart", "Start over…"))
	return result


func allows(id: String) -> bool:
	for choice: Dictionary in choices():
		if choice["id"] == id:
			return true
	return false


func choose(id: String) -> bool:
	if not allows(id):
		return false
	var label := ""
	for choice: Dictionary in choices():
		if choice["id"] == id:
			label = choice["label"]
	if id.begins_with("go_"):
		room = id.trim_prefix("go_")
		message = "You arrive at " + str(ROOMS[room]["title"]) + "."
	elif id.begins_with("retort_"):
		_reply(int(id.trim_prefix("retort_")))
	else:
		_act(id)
	revision += 1
	history.append("> " + label + "\n" + message)
	if history.size() > 8:
		history.pop_front()
	return true


func page() -> Dictionary:
	var names: Array[String] = []
	for item: String in inventory:
		names.append(ITEMS[item])
	return {
		"revision": revision,
		"title": TITLE,
		"place": "Curtain call" if won else ROOMS[room]["title"],
		"description": _description(),
		"message": message,
		"inventory": ", ".join(names) if not names.is_empty() else "Empty pockets",
		"history": "\n\n".join(history),
		"choices": choices()
	}


func _description() -> String:
	if confirming_restart:
		return "Start a new voyage? This erases only your own cabinet progress."
	if won:
		return "THE END — Thanks for playing Brine & Bureaucracy."
	if duel >= 0:
		return 'Quill, exchange %d of 3: "%s"' % [duel + 1, INSULTS[duel]]
	if room == "fort" and gate_open:
		return (
			"Quill sulks behind a stack of forms. "
			+ ("The locker is empty." if _has("bell") else "The customs locker is within reach.")
		)
	var text: String = ROOMS[room]["text"]
	if room == "quay":
		if fed_gull:
			text = text.replace("A gull guards a shiny token.", "A gull loudly enjoys its cracker.")
		if _has("magnet") or _has("fishing"):
			text = text.replace("A horseshoe magnet lies", "An empty magnet-shaped space lies")
		if _has("key"):
			text = text.replace("a small iron key glints just out of reach", "nothing else glints")
	elif room == "tavern" and (_has("cracker") or fed_gull):
		text = text.replace("A cracker sits", "A few crumbs sit")
	return text


func _act(id: String) -> void:
	match id:
		"look":
			message = _ending() if won else _description()
		"hint":
			message = _hint()
		"gull":
			message = "The gull says 'KRAA'. You translate: 'I accept payment in carbohydrates.'"
		"take_cracker":
			inventory.append("cracker")
			message = "You take the cracker. The bartender calls it last week's special."
		"take_magnet":
			inventory.append("magnet")
			message = "You pick up the magnet. It attracts iron, not admirers."
		"feed":
			inventory.erase("cracker")
			inventory.append("token")
			fed_gull = true
			message = "The gull exchanges its token for your cracker. The harbour's first fair deal."
		"merchant":
			message = (
				"'A token buys rope. A magnet catches iron. Tie them together and you "
				+ "have a long-distance bad idea.'"
			)
		"buy_rope":
			inventory.erase("token")
			inventory.append("rope")
			bought_rope = true
			message = "You buy the rope. The warranty expires while you read it."
		"combine":
			inventory.erase("rope")
			inventory.erase("magnet")
			inventory.append("fishing")
			message = "You tie the magnet to the rope. Finally: fishing without the fish."
		"fish":
			inventory.append("key")
			message = "The magnet lifts an iron key from the drain. Its tag says CUSTOMS LOCKER."
		"learn":
			learned = true
			message = (
				"Wake: 'Listen to the subject, then turn it around. Paperwork sinks ships? "
				+ "A filing cabinet is a reef. A receipt? Proof of purchase. Insignificant? "
				+ "At least you are filed correctly. Wit beats a sword, and costs less to polish.'"
			)
		"challenge":
			if learned:
				duel = 0
				message = "Quill draws a fountain pen. You draw on your limited experience."
			else:
				message = (
					"Quill demands three comebacks, not three grunts. Someone at the tavern "
					+ "might teach you. There is no shame in remedial piracy."
				)
		"retreat":
			duel = -1
			message = "You withdraw. Quill stamps your retreat APPROXIMATELY DIGNIFIED."
		"captain":
			message = "'Take the bell, then. I shall appeal to a higher stationery supplier.'"
		"unlock":
			inventory.append("bell")
			message = "You unlock the locker and recover the bell. It gives a deeply taxable ding."
		"sail":
			won = true
			message = _ending()
		"restart":
			confirming_restart = true
			message = "No coins required. No refunds on time spent being a pirate."
		"cancel_restart":
			confirming_restart = false
			message = "Your voyage continues."
		"confirm_restart":
			_reset()


func _reply(index: int) -> void:
	if index != duel:
		message = (
			"Quill: 'That remark belongs on a different form.' Try a comeback about "
			+ "what he actually said; no progress is lost."
		)
		return
	duel += 1
	if duel == 3:
		duel = -1
		gate_open = true
		message = "Quill's pen snaps. 'A crushing defeat. In triplicate.' He steps aside."
	else:
		message = "A direct hit to the ego! Quill rustles his next form."


# gdlint: disable=max-returns
func _hint() -> String:
	if duel >= 0:
		return RETORTS[duel] + " — Wake's advice: answer the subject of his insult."
	if _has("bell"):
		return "The boat at the quay is waiting for its bell."
	if gate_open and _has("key"):
		return "Try the iron key on the fort's customs locker."
	if not learned:
		return "Auntie Wake in the tavern knows how to win without a sword."
	if not fed_gull:
		return "That quay gull looks hungry. Check the tavern counter."
	if not bought_rope:
		return "Take your brass token to the chandlery."
	if not _has("fishing"):
		return "Pick up the quay's magnet, then combine it with rope."
	if not _has("key"):
		return "Iron in a drain? Your homemade fishing tool might reach it."
	return "Challenge Quill at the fort. Match each comeback to his subject."


func _ending() -> String:
	return (
		"You ring the bell. The boat sails before Quill can invent a departure tax. "
		+ "Auntie Wake waves; the gull invoices you for crumbs. You are now a pirate of "
		+ "modest renown and impeccable filing. Your treasure: one quiet afternoon. "
		+ "No casino money or backpack items were harmed. THE END."
	)


func _reset() -> void:
	room = "quay"
	inventory.clear()
	fed_gull = false
	bought_rope = false
	learned = false
	gate_open = false
	won = false
	duel = -1
	confirming_restart = false
	history.clear()
	message = INTRO


func _has(item: String) -> bool:
	return item in inventory


func _choice(id: String, label: String) -> Dictionary:
	return {"id": id, "label": label}
