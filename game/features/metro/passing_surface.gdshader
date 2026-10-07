shader_type spatial;
render_mode diffuse_lambert, specular_disabled;
// casino_hub's retro_surface for scenery that slides past a ride compartment.
// Textures stay world-anchored (no swimming as the camera turns) but shift with
// `scroll`, the scenery's travel along +Z, so they ride along with the walls.
// Shared by every ride: all trains run the same timetable, so one value fits all.

uniform sampler2D albedo_texture : source_color, filter_nearest_mipmap, repeat_enable;
uniform vec4 tint : source_color = vec4(1.0);
uniform float texture_scale = 0.25;
uniform float color_steps = 31.0;
uniform float scroll = 0.0;
varying vec3 world_position;
varying vec3 world_normal;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = MODEL_NORMAL_MATRIX * NORMAL;
}

void fragment() {
	vec3 p = world_position - vec3(0.0, 0.0, scroll);
	vec3 n = abs(world_normal);
	vec2 uv = n.y >= max(n.x, n.z) ? p.xz : (n.x > n.z ? p.zy : p.xy);
	vec3 color = texture(albedo_texture, uv * texture_scale).rgb * tint.rgb;
	// Two-by-two ordered dither, under one colour step; no screen-copy/postprocess pass.
	vec2 pixel = mod(floor(FRAGCOORD.xy), 2.0);
	float threshold = (pixel.x + pixel.y * 2.0) / 4.0 - 0.375;
	ALBEDO = clamp(floor(color * color_steps + 0.5 + threshold * 0.45) / color_steps, 0.0, 1.0);
	ROUGHNESS = 1.0;
}
