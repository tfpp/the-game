extends Node3D
## Local cosmetic poses driven by the shop's server-owned clock and serving state.


func present(phase: float, serving: float) -> void:
	$Spit.rotation.y = phase * 0.8
	$Chef/RightArm.rotation.x = -0.8 + sin(phase * 5.0) * 0.45
	$Chef/LeftArm.rotation.x = -0.45
	$Chef/Head.rotation.y = sin(phase * 0.8) * 0.18
	$Cashier/Head.rotation.y = sin(phase * 0.7) * 0.16
	$Cashier/RightArm.rotation.x = -0.7 if serving > 0.0 else -0.15
	$Cashier/LeftArm.rotation.z = 0.15 + sin(phase * 2.0) * 0.12
	$Reply.text = "Afiyet olsun! Enjoy your kebab!" if serving > 0.0 else "Hoş geldiniz! Welcome!"
