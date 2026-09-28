shader_type sky;

// Cross-fades between two equirectangular panoramas (day/night skyboxes) so the
// sky brightens and darkens smoothly with features/day_night/day_night.gd's clock,
// instead of just dimming the same daytime image at night.
uniform sampler2D day_texture: source_color, filter_nearest;
uniform sampler2D night_texture: source_color, filter_nearest;
uniform float blend: hint_range(0.0, 1.0) = 1.0;

void sky() {
	float phi = acos(clamp(EYEDIR.y, -1.0, 1.0));
	float theta = atan(EYEDIR.x, -EYEDIR.z);
	vec2 uv = vec2(theta / TAU + 0.5, phi / PI);
	vec3 day_color = texture(day_texture, uv).rgb;
	vec3 night_color = texture(night_texture, uv).rgb;
	COLOR = mix(night_color, day_color, blend);
}
