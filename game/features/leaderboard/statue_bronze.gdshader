shader_type spatial;
render_mode diffuse_lambert, specular_disabled;
uniform sampler2D grain : source_color, filter_nearest_mipmap;
uniform sampler2D face : source_color, filter_nearest_mipmap;
uniform float patina = 0.0;
uniform bool human = false;
uniform bool hide_head = false;
varying vec4 tags;

void vertex() {
	tags = COLOR;
}

void fragment() {
	if (human && hide_head && tags.b > 0.5) { discard; }
	float wear = texture(grain, UV).r;
	if (human && int(round(tags.r * 10.0)) == 7) {
		wear = dot(texture(face, clamp(UV, vec2(0.0), vec2(1.0))).rgb, vec3(0.333));
	}
	ALBEDO = mix(vec3(0.24, 0.13, 0.055), vec3(0.64, 0.43, 0.17), wear);
	ALBEDO *= 1.0 - patina;
	EMISSION = ALBEDO * 0.04;
	ROUGHNESS = 0.85;
}
