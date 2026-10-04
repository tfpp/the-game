shader_type spatial;
render_mode cull_disabled, diffuse_lambert, specular_disabled;

uniform sampler2D tree_texture : source_color, filter_nearest_mipmap, repeat_disable;
uniform float sway_amplitude = 0.16;
uniform float flutter_amplitude = 0.035;

void vertex() {
	// Fixed-Y billboard: remains upright even when the player looks up or down.
	vec3 facing = vec3(INV_VIEW_MATRIX[2].x, 0.0, INV_VIEW_MATRIX[2].z);
	facing = length(facing) > 0.001 ? normalize(facing) : vec3(0.0, 0.0, 1.0);
	vec3 right = cross(vec3(0.0, 1.0, 0.0), facing);
	vec3 scale = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz),
		length(MODEL_MATRIX[2].xyz));
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		vec4(right * scale.x, 0.0), vec4(0.0, scale.y, 0.0, 0.0),
		vec4(facing * scale.z, 0.0), MODEL_MATRIX[3]);
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	// Root/trunk stay planted. World-space phase prevents identical motion.
	float phase = dot(MODEL_MATRIX[3].xz, vec2(0.73, 0.31));
	float foliage = smoothstep(0.28, 1.0, 1.0 - UV.y);
	VERTEX.x += foliage * (sin(TIME * 1.35 + phase) * sway_amplitude
		+ sin(TIME * 4.7 + phase + UV.x * 5.0) * flutter_amplitude);
}

void fragment() {
	vec4 paint = texture(tree_texture, UV);
	ALBEDO = paint.rgb;
	ROUGHNESS = 1.0;
	ALPHA = paint.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
}
