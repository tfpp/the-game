shader_type spatial;
render_mode diffuse_burley;

varying vec3 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_position.xz * 1.4;
	vec2 cell = fract(p);
	float edge = min(min(cell.x, 1.0 - cell.x), min(cell.y, 1.0 - cell.y));
	float grout = 1.0 - smoothstep(0.012, 0.022 + fwidth(edge), edge);
	float checker = mod(floor(p.x) + floor(p.y), 2.0);
	float stone = sin(p.x * 6.0 + sin(p.y * 4.1)) * sin(p.y * 9.0 + p.x);
	vec3 color = mix(vec3(0.24, 0.33, 0.29), vec3(0.62, 0.61, 0.49), checker);
	color *= 0.94 + stone * 0.06;
	ALBEDO = mix(color, vec3(0.09, 0.10, 0.08), grout);
	ROUGHNESS = mix(0.38 + stone * 0.06, 0.94, grout);
	SPECULAR = 0.4;
}
