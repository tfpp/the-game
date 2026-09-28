shader_type spatial;
varying vec3 world_position;
void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	vec2 grid = fract(world_position.xz * 1.4);
	float grout = step(0.96, max(grid.x, grid.y));
	float checker = mod(floor(world_position.x * 1.4) + floor(world_position.z * 1.4), 2.0);
	ALBEDO = mix(vec3(0.26, 0.33, 0.28), vec3(0.38, 0.41, 0.31), checker);
	ALBEDO = mix(ALBEDO, vec3(0.12, 0.13, 0.10), grout);
	ROUGHNESS = 0.85;
}
