shader_type sky;
uniform float lightning = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}
float noise(vec2 p) {
	vec2 cell = floor(p);
	vec2 t = fract(p);
	t = t * t * (3.0 - 2.0 * t);
	return mix(mix(hash(cell), hash(cell + vec2(1,0)), t.x),
		mix(hash(cell + vec2(0,1)), hash(cell + vec2(1,1)), t.x), t.y);
}
void sky() {
	float altitude = max(EYEDIR.y, 0.0);
	vec2 p = EYEDIR.xz / (altitude + 0.24) * 3.0;
	float cloud = noise(p) * 0.55 + noise(p * 2.1) * 0.28 + noise(p * 4.3) * 0.17;
	vec3 cloud_color = mix(vec3(0.12, 0.16, 0.21), vec3(0.42, 0.47, 0.51), cloud);
	vec3 horizon = vec3(0.40, 0.46, 0.50);
	COLOR = mix(horizon, cloud_color, smoothstep(0.0, 0.38, altitude));
	if (EYEDIR.y < 0.0) {
		COLOR = mix(horizon, vec3(0.10, 0.13, 0.16), min(-EYEDIR.y * 3.0, 1.0));
	}
	COLOR = mix(COLOR, vec3(0.75, 0.82, 0.90), lightning);
}
