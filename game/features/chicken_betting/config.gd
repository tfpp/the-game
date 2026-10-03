class_name ChickenFightConfig
extends Resource
## All gameplay tuning belongs here; stat endpoints are inclusive.

@export var stat_min := 2
@export var stat_max := 10
@export var health_base := 30
@export var health_per_stamina := 3
@export var strength_weight := 3.0
@export var speed_weight := 2.0
@export var stamina_weight := 1.0
@export var luck_weight := 1.0
@export var damage_min := 3
@export var damage_max := 8
@export var strength_damage := 0.4
@export var house_edge := 0.02
@export var odds_samples := 1024
@export var probability_floor := 0.05
@export var min_bet_cents := 100
@export var max_bet_cents := 10000
@export var betting_seconds := 10.0
@export var round_seconds := 0.8
@export var result_seconds := 6.0
@export var refund_poll_seconds := 0.25
