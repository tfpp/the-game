class_name ScummArcadeCatalog
extends RefCounted
## Each cabinet owns one game and one durable save slot.

const GAMES := {
	"monkey":
	{
		"title": "Monkey Island",
		"marquee": "MONKEY ISLAND",
		"kicker": "THE SECRET OF",
		"subtitle": "A SHARED ADVENTURE",
		"color": Color("3c8992"),
		"badge": "",
		"interactive": true,
	},
	"samnmax":
	{
		"title": "Sam & Max: Hit the Road",
		"marquee": "SAM & MAX",
		"kicker": "FREELANCE POLICE",
		"subtitle": "HIT THE ROAD",
		"color": Color("a84437"),
		"badge": "S & M\nFREELANCE\nPOLICE",
		"interactive": true,
	},
	"atlantis":
	{
		"title": "Indiana Jones and the Fate of Atlantis",
		"marquee": "INDIANA JONES",
		"kicker": "LUCASARTS ADVENTURES",
		"subtitle": "THE FATE OF ATLANTIS",
		"color": Color("a37935"),
		"badge": "INDY\nATLANTIS",
		"interactive": true,
	},
	"pass":
	{
		"title": "Passport to Adventure",
		"marquee": "PASSPORT",
		"kicker": "THREE WORLDS TO EXPLORE",
		"subtitle": "TO ADVENTURE",
		"color": Color("436d9e"),
		"badge": "PASSPORT\nTO\nADVENTURE",
		"interactive": true,
	},
	"tentacle":
	{
		"title": "Day of the Tentacle",
		"marquee": "TENTACLE",
		"kicker": "DAY OF THE",
		"subtitle": "ANIMATED DEMO · WATCH TOGETHER",
		"color": Color("76549c"),
		"badge": "DOTT\nTIME\nTRAVEL",
		"interactive": false,
	},
}
