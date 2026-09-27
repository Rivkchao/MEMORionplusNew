shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

group_uniforms Base_Surface;
uniform vec4 albedo_color : source_color = vec4(0.2, 0.15, 0.55, 1.0);
uniform sampler2D albedo_texture : source_color, filter_linear_mipmap;
uniform sampler2D normal_texture : hint_normal, filter_linear_mipmap;
uniform float roughness : hint_range(0.0, 1.0) = 0.3;
uniform float metallic : hint_range(0.0, 1.0) = 0.05;

group_uniforms Ring_Reflection_Glow;
uniform vec4 ring_glow_color : source_color = vec4(0.0, 0.85, 1.0, 1.0);
uniform float ring_glow_intensity : hint_range(0.0, 10.0) = 2.5;
uniform float ring_glow_width : hint_range(0.01, 0.5) = 0.08;

group_uniforms Atmosphere_Rim;
uniform vec4 rim_color : source_color = vec4(0.7, 0.88, 1.0, 1.0);
uniform float rim_power : hint_range(1.0, 10.0) = 4.0;
uniform float rim_intensity : hint_range(0.0, 5.0) = 0.8;

varying vec3 v_local_pos;

void vertex() {
	v_local_pos = VERTEX;
}

void fragment() {
	vec4 tex_color = texture(albedo_texture, UV);
	ALBEDO = albedo_color.rgb * tex_color.rgb;
	ROUGHNESS = roughness;
	METALLIC = metallic;
	
	// Normal mapping
	vec3 n_tex = texture(normal_texture, UV).rgb;
	if (length(n_tex) > 0.1) {
		NORMAL_MAP = n_tex;
		NORMAL_MAP_DEPTH = 1.0;
	}
	
	// 1. Ring Reflection Glow (pantulan pendaran cincin di garis ekuator planet)
	float dist_y = abs(v_local_pos.y);
	float ring_bounce = exp(-pow(dist_y / ring_glow_width, 2.0));
	vec3 ring_emission = ring_glow_color.rgb * (ring_bounce * ring_glow_intensity);
	
	// 2. Subtle Atmospheric Fresnel Rim (siluet tipis atmosfer planet)
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), rim_power);
	vec3 rim_emission = rim_color.rgb * (fresnel * rim_intensity);
	
	EMISSION = ring_emission + rim_emission;
}
