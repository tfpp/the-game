extends GpsDestination
## The lounge appears in GPS after discovery, preserving the secret entrance.


func available() -> bool:
	var club := get_parent() as VipLounge
	return (
		super.available()
		and club != null
		and bool(club.profile(multiplayer.get_unique_id()).get("discovered", false))
	)
