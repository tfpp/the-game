shader_type spatial;
render_mode diffuse_burley;

uniform sampler2D symbols : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float reel_position = 0.0;

void fragment() {
	// Five equally spaced symbols. Crop the blank sides, not the original artwork.
	vec2 strip_uv = vec2(mix(0.33, 0.67, UV.x), (reel_position + 0.5 + (UV.y - 0.5) * 2.4) / 5.0);
	vec3 ink = texture(symbols, strip_uv).rgb;
	ALBEDO = ink;
	ROUGHNESS = 0.36;
	SPECULAR = 0.35;
	// A low backlight keeps the printed symbols legible at night.
	EMISSION = ink * 0.16;
}
