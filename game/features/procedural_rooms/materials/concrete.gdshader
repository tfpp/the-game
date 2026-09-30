shader_type spatial;
render_mode diffuse_burley;

uniform vec4 base_color : source_color = vec4(0.32, 0.35, 0.37, 1.0);
uniform float grid_strength = 0.09;
varying vec3 world_position;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_position.xz;
	float grain = hash(floor(p * 4.0));
	float patches = hash(floor(p * 0.7));
	vec2 grid = abs(fract(p / 1.6256 + 0.5) - 0.5);
	float line = 1.0 - smoothstep(0.006, 0.016, min(grid.x, grid.y));
	ALBEDO = base_color.rgb * (0.82 + grain * 0.17 + patches * 0.13);
	ALBEDO += vec3(line * grid_strength);
	ROUGHNESS = 0.94;
}
