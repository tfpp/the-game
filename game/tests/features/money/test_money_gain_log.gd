extends GutTest


class FakeChat:
	extends Node
	var notices: Array = []

	func send_notice(peer_id: int, text: String) -> void:
		notices.append([peer_id, text])


var _wallet: PlayerMoney
var _chat: FakeChat


func before_each() -> void:
	_chat = FakeChat.new()
	_chat.add_to_group(&"chat_box")
	add_child_autofree(_chat)
	_wallet = PlayerMoney.new()
	add_child_autofree(_wallet)
	_wallet.set_process(false)


func test_gain_text_names_amount_and_reason() -> void:
	assert_eq(PlayerMoney.gain_text(1000, "Picked up a coin"), "+$10.00: Picked up a coin")


func test_coin_credit_logs_its_reason() -> void:
	await _wallet.credit_coin(1, "one", "Picked up a coin")
	assert_eq(_chat.notices, [[1, "+$10.00: Picked up a coin"]])


func test_loot_sale_logs_its_amount() -> void:
	await _wallet.sell_loot(1, "one", 2550, "Sold loot to the fence")
	assert_eq(_chat.notices, [[1, "+$25.50: Sold loot to the fence"]])


func test_charges_and_zero_gains_are_not_logged() -> void:
	await _wallet.charge(1, "one", 500)
	_wallet.announce_gain(1, 0, "Nothing")
	assert_eq(_chat.notices, [])


func test_notice_line_has_no_sender_and_escapes_bbcode() -> void:
	var chat_script := load("res://features/chat_box/chat_box.gd")
	var line: String = chat_script.format_line("", "+$1.00: [b]x")
	assert_eq(line, "[color=#83e59b]+$1.00: [lb]b]x[/color]")


func test_money_groups_thousands_with_commas() -> void:
	assert_eq(PlayerMoney.format_money(0), "$0.00")
	assert_eq(PlayerMoney.format_money(5), "$0.05")
	assert_eq(PlayerMoney.format_money(99999), "$999.99")
	assert_eq(PlayerMoney.format_money(100000), "$1,000.00")
	assert_eq(PlayerMoney.format_money(123456789), "$1,234,567.89")
	assert_eq(PlayerMoney.format_money(100_000_000_000), "$1,000,000,000.00")
	assert_eq(PlayerMoney.format_money(-2566300), "-$25,663.00")
