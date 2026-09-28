shader_type spatial;
render_mode unshaded;

uniform sampler2D albedo_texture : source_color, filter_nearest_mipmap, repeat_enable;
uniform vec4 tint : source_color = vec4(1.0);
uniform float texture_scale = 0.25;
uniform float texture_inset = 0.0;
uniform float color_steps = 31.0;
// A small affine interpolation blend suggests console texture swim without moving targets.
uniform float affine_amount : hint_range(0.0, 0.15) = 0.04;
varying vec3 world_position;
varying vec3 world_normal;
varying vec3 affine_position;
varying float affine_w;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = MODEL_NORMAL_MATRIX * NORMAL;
	float clip_w = max(0.01, (PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).w);
	affine_position = world_position * clip_w;
	affine_w = clip_w;
}

void fragment() {
	vec3 p = mix(world_position, affine_position / max(affine_w, 0.01), affine_amount);
	vec3 n = abs(world_normal);
	vec2 uv = n.y >= max(n.x, n.z) ? p.xz : (n.x > n.z ? p.zy : p.xy);
	vec2 sample_uv = uv * texture_scale;
	if (texture_inset > 0.0) {
		sample_uv = fract(sample_uv) * (1.0 - 2.0 * texture_inset) + texture_inset;
	}
	vec3 color = texture(albedo_texture, sample_uv).rgb * tint.rgb;
	// Two-by-two ordered dither, under one colour step; no screen-copy/postprocess pass.
	vec2 pixel = mod(floor(FRAGCOORD.xy), 2.0);
	float threshold = (pixel.x + pixel.y * 2.0) / 4.0 - 0.375;
	vec3 pixel_color = clamp(floor(color * color_steps + 0.5 + threshold * 0.45) / color_steps, 0.0, 1.0);
	// Fixed warm indoor illumination stays legible when the outdoor clock turns to night.
	// Broad pools suggest the repeated ceiling fixtures without mobile shadow maps.
	vec2 lamp_offset = (fract((p.xz + vec2(4.0, 3.0)) / vec2(8.0, 6.0)) - 0.5) * vec2(8.0, 6.0);
	float pool = 0.72 + 0.28 / (1.0 + dot(lamp_offset, lamp_offset) * 0.18);
	float face = 0.78 + 0.22 * abs(world_normal.y);
	ALBEDO = pixel_color * pool * face * vec3(1.0, 0.9, 0.78);
}
