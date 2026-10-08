shader_type canvas_item;
// Drunk double vision: a wobbling ghost image, a slight smear and a dark vignette.
// Only drawn while the local player is intoxicated (DrunkView hides it otherwise).

uniform sampler2D screen_texture : hint_screen_texture, filter_linear;
uniform float strength : hint_range(0.0, 1.0) = 0.0;
uniform float time_s = 0.0;

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 wobble = vec2(sin(uv.y * 7.0 + time_s * 1.3), cos(uv.x * 5.0 + time_s * 1.1));
	uv += wobble * 0.004 * strength;
	vec2 ghost = vec2(sin(time_s * 0.9), cos(time_s * 0.7) * 0.4) * 0.022 * strength;
	vec3 base = texture(screen_texture, uv).rgb;
	vec3 left = texture(screen_texture, uv + ghost).rgb;
	vec3 right = texture(screen_texture, uv - ghost * 0.5).rgb;
	vec3 color = mix(base, (left + right) * 0.5, 0.45 * strength);
	float edge = smoothstep(0.32, 0.85, distance(SCREEN_UV, vec2(0.5)));
	color *= 1.0 - edge * 0.55 * strength;
	COLOR = vec4(color, 1.0);
}
