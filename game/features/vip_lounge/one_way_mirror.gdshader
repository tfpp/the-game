shader_type spatial;
render_mode cull_disabled;

// Outward-facing surface remains opaque. VIPs see through its back face.
// Match the adjacent upper stucco wall's authored front-face atlas and density.
// Never sample the screen buffer: it can reveal guests behind the facade.
uniform sampler2D stucco : source_color, filter_nearest_mipmap, repeat_disable;

void fragment() {
	if (!FRONT_FACING) {
		discard;
	}
	vec2 wall_uv = vec2((2.0 + fract(UV.x * 24.0) * 24.0) / 64.0,
		(32.0 + UV.y * 90.0) / 128.0);
	ALBEDO = texture(stucco, wall_uv).rgb;
	METALLIC = 0.0;
	ROUGHNESS = 0.95;
}
