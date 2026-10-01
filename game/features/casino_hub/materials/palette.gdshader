shader_type spatial;
render_mode diffuse_lambert, specular_disabled;

uniform sampler2D surface_atlas : filter_nearest_mipmap, repeat_disable;
varying vec3 baked_color;
varying flat float surface_kind;

void vertex() {
	surface_kind = floor(COLOR.a * 3.0 + 0.5);
	vec3 pigment = pow(max(COLOR.rgb, vec3(0.0)), vec3(0.5));
	baked_color = pigment;
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
	ROUGHNESS = 1.0;
}
