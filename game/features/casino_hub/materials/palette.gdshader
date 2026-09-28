shader_type spatial;
render_mode unshaded;

uniform sampler2D surface_atlas : filter_nearest_mipmap, repeat_disable;
varying vec3 baked_color;
varying flat float surface_kind;

void vertex() {
	surface_kind = floor(COLOR.a * 3.0 + 0.5);
	// Authored warm vertex illumination: no shadow maps or per-pixel light loops.
	// A small lift preserves the facets of dark suits and charcoal wall panels.
	vec3 n = normalize(MODEL_NORMAL_MATRIX * NORMAL);
	float face = 0.72 + 0.28 * max(dot(n, normalize(vec3(-0.3, 0.8, 0.5))), 0.0);
	vec3 pigment = pow(max(COLOR.rgb, vec3(0.0)), vec3(0.5));
	baked_color = pigment * vec3(1.0, 0.88, 0.73) * face;
	float lamp = step(0.8, COLOR.r) * step(0.5, COLOR.g);
	float screen = step(COLOR.r * 3.0, COLOR.b) * step(0.2, COLOR.b);
	baked_color = mix(baked_color, pigment, max(lamp, screen));
}

void fragment() {
	vec2 tile = vec2(mod(surface_kind, 2.0), floor(surface_kind / 2.0));
	// Keep sampling inside each 64-pixel tile, away from neighbouring atlas cells.
	vec2 atlas_uv = tile * 0.5 + vec2(0.015625) + fract(UV) * 0.46875;
	float grain = texture(surface_atlas, atlas_uv).r;
	float midpoint = surface_kind == 1.0 ? 0.39 : 0.56;
	float amount = surface_kind == 0.0 ? 0.25 : 1.0;
	float detail = clamp(1.0 + (grain - midpoint) * amount * 1.8, 0.72, 1.28);
	ALBEDO = baked_color * detail;
}
