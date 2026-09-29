shader_type canvas_item;
render_mode unshaded;

// Sample at native resolution, then quantize to five bits per RGB channel.
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;

void fragment() {
	vec3 color = textureLod(screen_texture, SCREEN_UV, 0.0).rgb;
	vec2 cell = mod(floor(FRAGCOORD.xy), 2.0);
	float threshold = (cell.y < 0.5 ? (cell.x < 0.5 ? 0.125 : 0.625)
		: (cell.x < 0.5 ? 0.875 : 0.375));
	COLOR = vec4(clamp(floor(color * 31.0 + threshold) / 31.0, 0.0, 1.0), 1.0);
}
