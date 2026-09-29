shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque, fog_disabled;

uniform sampler2D day_texture : source_color, filter_nearest;
uniform sampler2D night_texture : source_color, filter_nearest;
uniform float day_factor = 1.0;
varying vec3 world_point;

void vertex() {
	world_point = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 direction = normalize(world_point - CAMERA_POSITION_WORLD);
	vec2 uv = vec2(atan(direction.x, -direction.z) / TAU + 0.5,
		acos(clamp(direction.y, -1.0, 1.0)) / PI);
	ALBEDO = mix(texture(night_texture, uv).rgb, texture(day_texture, uv).rgb, day_factor);
}
