shader_type canvas_item;
render_mode unshaded, blend_disabled;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;
uniform float levels : hint_range(4.0, 256.0) = 256.0;

void fragment() {
	vec3 source = textureLod(screen_texture, SCREEN_UV, 0.0).rgb;
	float steps = max(levels - 1.0, 1.0);
	vec3 reduced = floor(clamp(source, vec3(0.0), vec3(1.0)) * steps + 0.5) / steps;
	COLOR = vec4(reduced, 1.0);
}
