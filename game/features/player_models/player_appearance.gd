class_name PlayerAppearance
extends RefCounted
## Bounded cosmetic options shared by the picker, server and avatar rig.

const OUTFITS: Array[String] = ["casual", "tactical"]
const HAIR_STYLES: Array[String] = ["classic", "crop", "swept", "long", "bald"]
const HAIR_COLORS: Array[Color] = [
	Color("30221b"), Color("77452b"), Color("ccab65"), Color("ab5032"), Color("a2a6ac")
]
const EYE_COLORS: Array[Color] = [
	Color("493326"), Color("3a7593"), Color("567b4a"), Color("79858a")
]


static func defaults() -> Dictionary:
	return {"skin": -1, "hair": "classic", "hair_color": 0, "eyes": 0, "outfit": "casual"}


static func valid(data: Dictionary) -> bool:
	if data.size() not in [4, 5] or not data.has_all(["skin", "hair", "hair_color", "eyes"]):
		return false
	if data.size() == 5 and (not data.has("outfit") or data["outfit"] not in OUTFITS):
		return false
	if data["hair"] is not String or data["hair"] not in HAIR_STYLES:
		return false
	for key: String in ["skin", "hair_color", "eyes"]:
		var value: Variant = data[key]
		if not (value is int or value is float) or not is_finite(float(value)):
			return false
		if float(value) != floorf(float(value)):
			return false
	return (
		int(data["skin"]) >= -1
		and int(data["skin"]) < PlayerSkin.TONES.size()
		and int(data["hair_color"]) >= 0
		and int(data["hair_color"]) < HAIR_COLORS.size()
		and int(data["eyes"]) >= 0
		and int(data["eyes"]) < EYE_COLORS.size()
	)
