shader_type spatial;
render_mode diffuse_lambert, specular_disabled;

uniform sampler2D albedo_texture : source_color, filter_nearest_mipmap, repeat_enable;
uniform vec4 tint : source_color = vec4(1.0);
uniform float texture_scale = 0.25;
uniform float texture_inset = 0.0;
uniform float color_steps = 31.0;
varying vec3 world_position;
varying vec3 world_normal;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = MODEL_NORMAL_MATRIX * NORMAL;
}

void fragment() {
	// World-anchored mapping: textures must not swim when the camera turns.
	vec3 p = world_position;
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
	ALBEDO = pixel_color;
	ROUGHNESS = 1.0;
}
