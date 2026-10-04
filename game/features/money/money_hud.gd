extends CanvasLayer
## Shows the local player's wallet as a small coin-and-balance chip in the top-left
## corner, inside the safe area and apart from features/combat's HP bar. Placed by
## ui/hud_layout.gd, which also hides it under the pause menu.

var _placed_for := ""

@onready var _wallet: Control = $Wallet
@onready var _amount: Label = $Wallet/Row/Amount


func _process(_delta: float) -> void:
	_wallet.visible = not HudLayout.paused(get_tree())
	var key := HudLayout.layout_key(self)
	if key != _placed_for:
		_placed_for = key
		HudLayout.place(_wallet, HudLayout.Piece.MONEY)
	var money := get_parent() as PlayerMoney
	if money == null:
		return
	_amount.text = wallet_text(money.balances, multiplayer.get_unique_id())


## "$12.50", or "…" until the server has sent this peer's balance.
static func wallet_text(balances: Dictionary, peer: int) -> String:
	return PlayerMoney.format_money(int(balances[peer])) if balances.has(peer) else "…"
