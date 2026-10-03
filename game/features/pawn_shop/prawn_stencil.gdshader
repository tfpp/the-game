shader_type spatial;
render_mode blend_mix, specular_disabled;
varying vec3 local_position;
varying vec3 local_normal;
void vertex() {
	local_position = VERTEX;
	local_normal = NORMAL;
}
void fragment() {
	// Reuse the wooden crate mesh/atlas, with a coarse cream prawn stencil.
	vec2 p = floor(local_position.xy * 32.0) / 32.0 - vec2(0.0, 0.5);
	float body = step(0.11, length(p)) * (1.0 - step(0.21, length(p)));
	body *= step(-0.14, p.x) * step(-0.16, p.y);
	float tail = step(0.04, p.x) * step(-0.19, p.y) * (1.0 - step(-0.09, p.y));
	tail *= 1.0 - step(0.19 + p.y * 0.3, p.x);
	float eye = 1.0 - step(0.024, length(p - vec2(-0.09, 0.13)));
	ALBEDO = vec3(0.78, 0.68, 0.48);
	ROUGHNESS = 0.9;
	ALPHA = max(body, tail) * (1.0 - eye) * step(0.8, local_normal.z) * 0.85;
}
