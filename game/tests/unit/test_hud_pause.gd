extends GutTest
## Opening the pause menu (ui/login/login_screen.gd) hides every gameplay HUD piece and
## the touch controls, and the menu renders above all HUD layers.

const Login := preload("res://ui/login/login_screen.gd")
const HudScene := preload("res://ui/hud.tscn")
const MoneyScene := preload("res://features/money/feature.tscn")
const CombatScene := preload("res://features/combat/feature.tscn")
const Overlay := preload("res://features/touch_controls/touch_controls.gd")

var _device: Controls.Device
var _touch: bool


func before_each() -> void:
	_device = Controls.device
	_touch = Controls.touch_available


func after_each() -> void:
	Controls.device = _device
	Controls.touch_available = _touch
	Controls.pause()


func test_opening_the_menu_hides_all_hud_and_closing_restores_it() -> void:
	Controls.device = Controls.Device.TOUCH
	Controls.touch_available = true
	var hud := HudScene.instantiate() as CanvasLayer
	add_child_autofree(hud)
	var money := MoneyScene.instantiate()
	add_child_autofree(money)
	var combat := CombatScene.instantiate()
	add_child_autofree(combat)
	var overlay := Overlay.new()
	overlay.size = Vector2(1280, 720)
	add_child_autofree(overlay)
	var menu := Login.new()
	add_child_autofree(menu)
	var wallet := money.get_node("Hud/Wallet") as Control
	var health := combat.get_node("Hud/Health") as Control
	Controls.start()
	menu._open()
	await wait_process_frames(2)
	assert_true(HudLayout.paused(get_tree()))
	assert_false(hud.visible, "Crosshair, VOICE and version hide")
	assert_false(wallet.visible)
	assert_false(health.visible)
	assert_false(overlay.visible, "Joystick and action buttons hide")
	menu._close()
	Controls.start()
	await wait_process_frames(2)
	assert_false(HudLayout.paused(get_tree()))
	assert_true(hud.visible)
	assert_true(wallet.visible)
	assert_true(health.visible)
	assert_true(overlay.visible)


func test_menu_draws_above_every_hud_layer() -> void:
	var menu := Login.new()
	add_child_autofree(menu)
	var combat := CombatScene.instantiate()
	add_child_autofree(combat)
	assert_gt(menu.layer, (combat.get_node("Hud") as CanvasLayer).layer)
	assert_gt(menu.layer, 30, "Above the emote wheel and touch controls")


func test_touch_controls_leave_taps_on_the_hotbar_to_the_hud() -> void:
	Controls.device = Controls.Device.TOUCH
	Controls.touch_available = true
	Controls.start()
	var overlay := Overlay.new()
	overlay.size = Vector2(1280, 720)
	add_child_autofree(overlay)
	var panel := Control.new()
	panel.position = Vector2(500, 20)
	panel.size = Vector2(300, 80)
	panel.add_to_group(&"touch_hud")
	add_child_autofree(panel)
	var touch := InputEventScreenTouch.new()
	touch.index = 3
	touch.pressed = true
	touch.position = Vector2(600, 50)
	overlay._input(touch)
	assert_eq(overlay.look_finger, -1, "The hotbar tap is not a look swipe")
	touch.position = Vector2(900, 400)
	overlay._input(touch)
	assert_eq(overlay.look_finger, 3, "Elsewhere still looks around")
