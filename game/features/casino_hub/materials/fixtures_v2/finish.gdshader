shader_type spatial;
uniform sampler2D atlas : source_color, filter_nearest_mipmap;
void fragment() {
    vec3 paint = texture(atlas, UV).rgb;
    bool glass = UV.x > 0.5;
    ALBEDO = paint;
    ROUGHNESS = glass ? 0.8 : 0.45;
    METALLIC = glass ? 0.0 : 0.4;
    EMISSION = glass ? paint * vec3(0.3, 0.21, 0.12) : vec3(0.0);
}
