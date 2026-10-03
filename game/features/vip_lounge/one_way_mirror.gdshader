shader_type spatial;
render_mode cull_disabled;

// Outward-facing surface remains opaque. VIPs see through its back face.
// Opaque chrome outside. Never sample the screen buffer: it can contain guests
// drawn behind this pane and accidentally expose them in a fake reflection.

void fragment() {
	if (!FRONT_FACING) {
		discard;
	}
	ALBEDO = vec3(0.32, 0.35, 0.37);
	METALLIC = 0.9;
	ROUGHNESS = 0.18;
}
