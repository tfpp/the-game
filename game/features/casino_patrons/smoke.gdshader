shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;

// Camera-facing wisps, preserving each CPU particle's expanding scale.
void vertex() {
	mat4 facing = mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1],
		INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	facing[0].xyz *= length(MODEL_MATRIX[0].xyz);
	facing[1].xyz *= length(MODEL_MATRIX[1].xyz);
	facing[2].xyz *= length(MODEL_MATRIX[2].xyz);
	MODELVIEW_MATRIX = VIEW_MATRIX * facing;
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	p.x += 0.12 * sin(p.y * 7.0 + TIME * 1.4);
	float cloud = 1.0 - smoothstep(0.15, 1.0, length(p));
	ALBEDO = vec3(0.72, 0.73, 0.70) * COLOR.rgb;
	ALPHA = cloud * cloud * COLOR.a * 0.38;
}
