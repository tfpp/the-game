shader_type spatial;
render_mode specular_disabled, cull_disabled;

uniform sampler2D albedo_texture : source_color, filter_nearest_mipmap, repeat_enable;
uniform vec4 albedo_tint : source_color = vec4(1.0);
uniform vec2 texture_scale = vec2(1.0);

void fragment() {
	vec3 surface = texture(albedo_texture, UV * texture_scale).rgb * albedo_tint.rgb * COLOR.rgb;
	ALBEDO = surface;
	ROUGHNESS = 1.0;
	// Godot supplies the UV2 lightmap and baked probes through LightmapGI.
}

void light() {
	// The static room's lighting is baked. Moving flashlights can still add light,
	// while the outdoor day/night sun cannot shine through walls on mobile.
	if (!LIGHT_IS_DIRECTIONAL) {
		DIFFUSE_LIGHT += max(dot(NORMAL, LIGHT), 0.0) * ATTENUATION * LIGHT_COLOR / PI;
	}
}
