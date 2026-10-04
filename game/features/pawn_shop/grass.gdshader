shader_type spatial;
render_mode diffuse_lambert, specular_disabled;

varying vec3 ground_position;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	ground_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 cell = floor(ground_position.xz * 8.0);
	float fleck = hash(cell);
	float patch = hash(floor(ground_position.xz * 0.6));
	ALBEDO = mix(vec3(0.10, 0.14, 0.065), vec3(0.22, 0.27, 0.11), fleck * 0.6 + patch * 0.4);
	ROUGHNESS = 1.0;
}
