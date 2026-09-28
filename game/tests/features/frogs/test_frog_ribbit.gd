extends GutTest
## Procedurally synthesized ribbit cue (features/frogs/frog_ribbit.gd), played by
## Frog._explode when a frog is shot (see test_frog_death.gd).

const FrogRibbit := preload("res://features/frogs/frog_ribbit.gd")
const FROG := preload("res://features/frogs/frog.tscn")


func test_stream_is_a_short_mono_16_bit_clip() -> void:
	var stream := FrogRibbit.stream()
	assert_eq(stream.format, AudioStreamWAV.FORMAT_16_BITS)
	assert_false(stream.stereo)
	assert_eq(stream.mix_rate, FrogRibbit.MIX_RATE)
	assert_gt(stream.data.size(), 0)
	var duration_s := float(stream.data.size()) / 2.0 / FrogRibbit.MIX_RATE
	assert_between(duration_s, 0.05, 0.5)


func test_stream_is_cached_across_calls() -> void:
	assert_same(FrogRibbit.stream(), FrogRibbit.stream())


func test_taking_a_hit_plays_the_ribbit_cue() -> void:
	var frog := FROG.instantiate() as Frog
	add_child_autofree(frog)
	frog.set_physics_process(false)
	var ribbit := frog.get_node("Ribbit") as AudioStreamPlayer3D
	assert_eq(ribbit.stream, FrogRibbit.stream())
	frog.take_hit(1)
	assert_true(ribbit.playing)
