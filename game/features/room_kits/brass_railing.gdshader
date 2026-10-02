shader_type spatial;
render_mode diffuse_lambert;

uniform sampler2D albedo_texture : source_color, filter_nearest_mipmap;
varying vec3 finish_color;
varying float brass;

void fragment() {
	finish_color = texture(albedo_texture, UV).rgb;
	brass = UV.x < 0.5 ? 1.0 : 0.0;
	ALBEDO = finish_color;
	ROUGHNESS = mix(0.9, 0.3, brass);
	METALLIC = brass * 0.45;
}

void light() {
	float diffuse = max(dot(NORMAL, LIGHT), 0.0);
	DIFFUSE_LIGHT += diffuse * LIGHT_COLOR * ATTENUATION / PI;
	// A restrained, light-dependent gold highlight. Casino lamps suppress generic
	// specular; this finish keeps polished brass readable without changing other props.
	vec3 half_vector = normalize(LIGHT + VIEW);
	float highlight = pow(max(dot(NORMAL, half_vector), 0.0), 32.0);
	SPECULAR_LIGHT += brass * highlight * vec3(1.0, 0.82, 0.42) * LIGHT_COLOR * ATTENUATION * 0.35;
}
