shader_type spatial;
render_mode cull_back, diffuse_lambert, specular_disabled;

uniform sampler2D face_texture : source_color, filter_nearest_mipmap, repeat_disable;
uniform sampler2D skin_texture : source_color, filter_nearest_mipmap, repeat_enable;
uniform sampler2D fabric_texture : source_color, filter_nearest_mipmap, repeat_enable;
uniform sampler2D trousers_texture : source_color, filter_nearest_mipmap, repeat_enable;
uniform sampler2D hair_texture : source_color, filter_nearest_mipmap, repeat_enable;
uniform sampler2D gear_texture : source_color, filter_nearest_mipmap, repeat_enable;
uniform sampler2D leather_texture : source_color, filter_nearest_mipmap, repeat_enable;
uniform sampler2D tux_texture : source_color, filter_nearest_mipmap, repeat_enable;
uniform vec4 skin_tint : source_color = vec4(0.8, 0.6, 0.4, 1.0);
uniform vec4 shirt_tint : source_color = vec4(0.5, 0.5, 0.5, 1.0);
uniform vec4 pants_tint : source_color = vec4(0.3, 0.3, 0.3, 1.0);
uniform vec4 hair_tint : source_color = vec4(0.12, 0.08, 0.05, 1.0);
uniform vec4 eye_tint : source_color = vec4(0.15, 0.1, 0.05, 1.0);
uniform bool shirt_equipped = false;
uniform bool pants_equipped = false;
uniform bool tactical = false;
uniform bool tuxedo = false;
uniform bool hair_enabled = true;
uniform bool hide_head = false;
uniform bool hide_left_arm = false;
uniform bool hide_right_arm = false;
uniform bool arms_only = false;
uniform bool right_leg_only = false;
varying vec4 tags;
varying vec2 rest_xy;
varying float front;

void vertex() {
	tags = COLOR;
	rest_xy = vec2(UV2.x, 1.0 - UV2.y);
	front = -NORMAL.z;
}

void fragment() {
	if (right_leg_only && (rest_xy.x < 0.0 || rest_xy.y > -0.17 || tags.g < 0.2 || tags.g > 0.8)) { discard; }
	if (arms_only && tags.g > 0.2 && tags.g < 0.8) { discard; }
	if ((hide_head && tags.b > 0.5) || (hide_left_arm && tags.g < 0.2) || (hide_right_arm && tags.g > 0.8)) {
		discard;
	}
	int role = int(round(tags.r * 10.0));
	float facing = cos((UV.x - 0.5) * 6.2831853);
	bool arm = tags.g < 0.2 || tags.g > 0.8;
	vec2 painted_uv = UV;
	if (role != 7 && role != 3 && rest_xy.y < 0.52) {
		role = 0;
		if ((arm && rest_xy.y > 0.045) || (!arm && rest_xy.y > -0.16 && rest_xy.y < 0.455)) { role = 1; }
		if (!arm && rest_xy.y < -0.16 && rest_xy.y > -0.79) { role = 2; }
		if (rest_xy.y < -0.79) { role = 6; }
		if (tactical && !arm && abs(rest_xy.x) < 0.19 && rest_xy.y > 0.015 && rest_xy.y < 0.39 && facing > 0.3) { role = 5; }
		painted_uv.y = (rest_xy.y + 0.17) / 0.62;
		if (role == 2) { painted_uv.y = (-rest_xy.y - 0.17) / 0.64; }
		if (role == 5) { painted_uv = vec2(0.5 + rest_xy.x / 0.4, (rest_xy.y - 0.015) / 0.375); }
	}
	vec3 artwork = texture(skin_texture, painted_uv).rgb;
	vec3 tint = skin_tint.rgb;
	if (role == 1 || role == 5) {
		if (tactical || shirt_equipped) {
			artwork = texture(fabric_texture, painted_uv).rgb;
			tint = shirt_tint.rgb;
		}
		if (tuxedo) {
			// The back UV seam interpolates through the white front; keep the back vest black.
			vec2 tux_uv = front > 0.0 ? painted_uv : vec2(0.0, painted_uv.y);
			artwork = arm ? texture(fabric_texture, painted_uv).rgb : textureLod(tux_texture, tux_uv, 0.0).rgb;
			tint = arm ? vec3(0.95) : vec3(1.0);
		}
		if (role == 5 && tactical) {
			artwork = texture(gear_texture, painted_uv).rgb;
			tint = vec3(0.17, 0.19, 0.15);
		}
	} else if (role == 2) {
		if (tactical || pants_equipped) {
			artwork = texture(trousers_texture, painted_uv).rgb;
			tint = pants_tint.rgb;
		} else if (painted_uv.y < 0.23) {
			artwork = texture(fabric_texture, painted_uv).rgb;
			tint = vec3(0.94);
		}
	} else if (role == 3 && hair_enabled) {
		artwork = texture(hair_texture, UV).rgb;
		tint = hair_tint.rgb;
	} else if (role == 6 && (tactical || pants_equipped)) {
		artwork = texture(leather_texture, painted_uv).rgb;
		tint = tactical ? vec3(0.12, 0.13, 0.11) : vec3(0.20, 0.18, 0.15);
	} else if (role == 7) {
		artwork = texture(face_texture, clamp(UV, vec2(0.0), vec2(1.0))).rgb;
		vec2 eye_center = vec2(UV.x < 0.5 ? 0.265 : 0.735, 0.60);
		float iris = 1.0 - smoothstep(0.65, 1.0, length((UV - eye_center) / vec2(0.022, 0.018)));
		tint = mix(tint, eye_tint.rgb * 0.7, iris);
	}
	ALBEDO = artwork * tint;
	ROUGHNESS = 1.0;
}
