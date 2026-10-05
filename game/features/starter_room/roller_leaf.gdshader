shader_type spatial;
render_mode cull_back;
uniform sampler2D paint : source_color, filter_nearest_mipmap;
uniform float lift_height = 0.0;
varying float panel_y;
void vertex() { panel_y = VERTEX.y; }
void fragment() {
	if (panel_y + lift_height > 3.2) { discard; }
	ALBEDO = texture(paint, UV).rgb;
	ROUGHNESS = 0.86;
}
