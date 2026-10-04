extends CanvasLayer
## Shows the local player's wallet just above features/combat's HP bar. Both are placed
## by ui/hud_layout.gd: bottom-right on wide screens, stacked with the weapon panel on
## narrow and touch screens.

var _placed_for := ""

@onready var _wallet: Control = $Wallet
@onready var _amount: Label = $Wallet/Row/Amount


func _process(_delta: float) -> void:
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
