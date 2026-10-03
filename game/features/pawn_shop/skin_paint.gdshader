shader_type spatial;
render_mode specular_disabled;
uniform vec4 paint : source_color;
uniform vec4 shell : source_color;
uniform float pattern = 0.0;
void fragment() {
	// Coarse repeated shell segments and curled prawn stamps, not texture assets.
	vec2 p = floor(UV * 32.0) / 32.0;
	vec2 stamp = fract(p * 2.0) - vec2(0.5);
	float curl = step(0.16, length(stamp)) * (1.0 - step(0.32, length(stamp)));
	curl *= step(-0.20, stamp.x) * step(-0.25, stamp.y);
	float ribs = step(0.7, fract((p.x + p.y * 0.3) * (5.0 + pattern)));
	ALBEDO = mix(paint.rgb, shell.rgb, max(curl, ribs * 0.4));
	ROUGHNESS = 0.8;
}
