shader_type spatial;
render_mode diffuse_burley;

varying vec3 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_position.xz;
	vec2 tile = mod(p, 1.6) - 0.8;
	float diamond = abs(tile.x) + abs(tile.y);
	float border = 1.0 - smoothstep(0.045, 0.075, abs(diamond - 0.58));
	float petal = 1.0 - smoothstep(0.06, 0.1, abs(length(tile * vec2(1.0, 1.8)) - 0.29));
	float fleck = fract(sin(dot(floor(p * 170.0), vec2(127.1, 311.7))) * 43758.5453);
	float wear = smoothstep(-0.3, 0.8, sin(p.x * 0.7) * cos(p.y * 0.46));
	vec3 color = mix(vec3(0.19, 0.025, 0.055), vec3(0.36, 0.18, 0.13), wear * 0.6);
	color = mix(color, vec3(0.62, 0.39, 0.11), border * 0.75);
	color = mix(color, vec3(0.11, 0.32, 0.27), petal * 0.8);
	ALBEDO = color * (0.8 + fleck * 0.3);
	ROUGHNESS = 1.0;
}
