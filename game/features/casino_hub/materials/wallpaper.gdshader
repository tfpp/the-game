shader_type spatial;

varying vec3 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float u = world_position.x + world_position.z;
	float stripe = step(0.72, fract(u * 1.2));
	float motif = pow(abs(sin(u * 3.8) * sin(world_position.y * 2.8)), 8.0);
	float grime = 0.8 + 0.2 * sin(u * 0.43 + sin(world_position.y * 3.0));
	ALBEDO = mix(vec3(0.39, 0.43, 0.18), vec3(0.62, 0.38, 0.16), stripe);
	ALBEDO = mix(ALBEDO, vec3(0.15, 0.29, 0.26), motif * 0.85) * grime;
	ROUGHNESS = 0.95;
}
