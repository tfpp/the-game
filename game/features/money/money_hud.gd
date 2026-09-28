extends CanvasLayer
## Shows the local player's wallet in the bottom-right corner, just above
## features/combat's health bar (bottom 20-44 px); the two stay lined up by sharing
## the corner's 16 px right margin.

@onready var _amount: Label = $Wallet/Amount


func _process(_delta: float) -> void:
	var money := get_parent() as PlayerMoney
	if money == null:
		return
	_amount.text = wallet_text(money.balances, multiplayer.get_unique_id())


## "$12.50", or "…" until the server has sent this peer's balance.
static func wallet_text(balances: Dictionary, peer: int) -> String:
	return PlayerMoney.format_money(int(balances[peer])) if balances.has(peer) else "…"
