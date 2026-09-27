shader_type spatial;
render_mode unshaded, cull_front;

// ============================================================
// COLOR / SATURATION
// ============================================================

group_uniforms color_adjustment;

uniform float saturation : hint_range(0.0, 3.0) = 1.15;


// ============================================================
// BACKGROUND & NEBULA
// ============================================================

group_uniforms background_and_nebula;

// Palet berdasarkan gambar referensi
uniform vec3 deep_space_color : source_color =
    vec3(0.024, 0.020, 0.035);       // #06050A

uniform vec3 deep_navy : source_color =
    vec3(0.055, 0.075, 0.095);       // #0E1318

uniform vec3 nebula_cyan : source_color =
    vec3(0.055, 0.200, 0.240);       // #0E333D

uniform vec3 nebula_teal : source_color =
    vec3(0.055, 0.145, 0.170);       // #0E252B

uniform vec3 nebula_purple : source_color =
    vec3(0.150, 0.090, 0.170);       // #26172B

uniform vec3 nebula_magenta : source_color =
    vec3(0.235, 0.047, 0.137);       // #3C0C23

uniform vec3 nebula_wine : source_color =
    vec3(0.400, 0.055, 0.220);       // #660E38


uniform float nebula_scale : hint_range(0.5, 6.0) = 2.2;

uniform float nebula_density : hint_range(0.1, 3.0) = 1.0;


// ============================================================
// STAR SETTINGS
// ============================================================

group_uniforms star_settings;

uniform float star_density : hint_range(50.0, 350.0) = 160.0;

uniform float star_brightness : hint_range(0.5, 5.0) = 1.65;

uniform float twinkle_speed : hint_range(0.1, 6.0) = 2.0;


varying vec3 world_dir;


// ============================================================
// HASH
// ============================================================

vec3 hash33(vec3 p) {

    p = fract(
        p * vec3(
            0.1031,
            0.1030,
            0.0973
        )
    );

    p += dot(
        p,
        p.yxz + 33.33
    );

    return fract(
        (p.xxy + p.yxx) * p.zyx
    );
}


float hash13(vec3 p) {

    p = fract(
        p * 0.1031
    );

    p += dot(
        p,
        p.zyx + 31.32
    );

    return fract(
        (p.x + p.y) * p.z
    );
}


// ============================================================
// 3D NOISE
// ============================================================

float noise3d(vec3 p) {

    vec3 i = floor(p);
    vec3 f = fract(p);

    f = f * f * (3.0 - 2.0 * f);

    return mix(

        mix(
            mix(
                hash13(i + vec3(0, 0, 0)),
                hash13(i + vec3(1, 0, 0)),
                f.x
            ),

            mix(
                hash13(i + vec3(0, 1, 0)),
                hash13(i + vec3(1, 1, 0)),
                f.x
            ),

            f.y
        ),

        mix(
            mix(
                hash13(i + vec3(0, 0, 1)),
                hash13(i + vec3(1, 0, 1)),
                f.x
            ),

            mix(
                hash13(i + vec3(0, 1, 1)),
                hash13(i + vec3(1, 1, 1)),
                f.x
            ),

            f.y
        ),

        f.z
    );
}


// ============================================================
// FBM
// ============================================================

float fbm(vec3 p) {

    float val = 0.0;
    float amp = 0.5;

    mat3 rot = mat3(

        vec3(
            0.00,
            0.80,
            0.60
        ),

        vec3(
            -0.80,
            0.36,
            -0.48
        ),

        vec3(
            -0.60,
            -0.48,
            0.64
        )
    );

    for (int i = 0; i < 4; i++) {

        val += amp * noise3d(p);

        p = rot * p * 2.02;

        amp *= 0.5;
    }

    return val;
}


// ============================================================
// STAR LAYER
// ============================================================

vec3 render_stars_layer(
    vec3 dir,
    float scale,
    float speed
) {

    vec3 p = dir * scale;

    vec3 id = floor(p);

    vec3 gv = fract(p) - 0.5;

    vec3 star_acc = vec3(0.0);


    for (int z = -1; z <= 1; z++) {

        for (int y = -1; y <= 1; y++) {

            for (int x = -1; x <= 1; x++) {

                vec3 offset = vec3(
                    float(x),
                    float(y),
                    float(z)
                );

                vec3 rnd =
                    hash33(id + offset);


                vec3 star_pos =
                    offset +
                    (rnd - 0.5) * 0.8;


                float dist =
                    length(
                        gv - star_pos
                    );


                float sharpness =
                    mix(
                        40.0,
                        160.0,
                        rnd.y
                    );


                float phase =
                    rnd.x * 6.2831853;


                float freq =
                    0.6 +
                    rnd.z * 1.8;


                // --------------------------------------------
                // TWINKLE
                // --------------------------------------------

                float twinkle =
                    sin(
                        TIME *
                        speed *
                        freq +
                        phase
                    ) * 0.5 + 0.5;


                twinkle =
                    smoothstep(
                        0.1,
                        0.9,
                        twinkle
                    );


                float size_factor =
                    1.0 -
                    rnd.y * 0.4;


                float intensity =
                    exp(
                        -dist * sharpness
                    ) *
                    twinkle *
                    size_factor;


                // --------------------------------------------
                // STAR COLOR
                // --------------------------------------------

                vec3 star_tint =
                    mix(
                        vec3(
                            0.70,
                            0.82,
                            0.90
                        ),

                        vec3(
                            1.00,
                            0.72,
                            0.82
                        ),

                        rnd.z
                    );


                star_tint =
                    mix(
                        star_tint,
                        vec3(1.0),
                        rnd.x * 0.55
                    );


                star_acc +=
                    star_tint *
                    intensity;
            }
        }
    }

    return star_acc;
}


// ============================================================
// VERTEX
// ============================================================

void vertex() {

    world_dir =
        (MODEL_MATRIX *
        vec4(VERTEX, 1.0)).xyz;
}


// ============================================================
// FRAGMENT
// ============================================================

void fragment() {

    vec3 dir =
        normalize(world_dir);


    // ========================================================
    // 1. NEBULA COORDINATES
    // ========================================================

    vec3 neb_coords =
        dir * nebula_scale;


    float base_n =
        fbm(
            neb_coords
        );


    float detail_n =
        fbm(
            neb_coords +
            base_n * 1.5
        );


    // ========================================================
    // 2. SOFT NEBULA MASK
    // ========================================================

    float soft_cloud =
        smoothstep(
            0.30,
            0.78,
            base_n
        );


    float detail_cloud =
        smoothstep(
            0.38,
            0.78,
            detail_n
        );


    // ========================================================
    // 3. CYAN / TEAL
    // ========================================================

    float cyan_mask =
        smoothstep(
            0.40,
            0.78,

            fbm(
                neb_coords * 1.25 +
                vec3(
                    4.2,
                    1.7,
                    -2.5
                )
            )
        );


    float teal_mask =
        smoothstep(
            0.35,
            0.72,

            fbm(
                neb_coords * 0.85 +
                vec3(
                    -3.0,
                    2.5,
                    4.0
                )
            )
        );


    // ========================================================
    // 4. PURPLE
    // ========================================================

    float purple_mask =
        smoothstep(
            0.32,
            0.76,

            fbm(
                neb_coords * 1.05 +
                vec3(
                    2.5,
                    -4.0,
                    1.5
                )
            )
        );


    // ========================================================
    // 5. MAGENTA
    // ========================================================

    float magenta_mask =
        smoothstep(
            0.43,
            0.78,

            fbm(
                neb_coords * 1.15 +
                vec3(
                    -4.0,
                    3.0,
                    -1.5
                )
            )
        );


    // ========================================================
    // 6. WINE / PINK HIGHLIGHT
    // ========================================================

    float wine_mask =
        smoothstep(
            0.58,
            0.84,
            detail_n
        );


    // ========================================================
    // 7. BUILD NEBULA
    // ========================================================

    vec3 nebula =
        deep_space_color;


    // Dark navy atmospheric base

    nebula +=
        deep_navy *
        soft_cloud *
        0.35;


    // Cyan

    nebula +=
        nebula_cyan *
        cyan_mask *
        soft_cloud *
        0.95;


    // Teal

    nebula +=
        nebula_teal *
        teal_mask *
        soft_cloud *
        0.75;


    // Purple

    nebula +=
        nebula_purple *
        purple_mask *
        soft_cloud *
        0.90;


    // Magenta

    nebula +=
        nebula_magenta *
        magenta_mask *
        detail_cloud *
        0.85;


    // Wine highlight

    nebula +=
        nebula_wine *
        wine_mask *
        magenta_mask *
        0.35;


    // ========================================================
    // 8. SUBTLE NEBULA FALLOFF
    // ========================================================

    nebula *=
        mix(
            0.72,
            1.0,
            soft_cloud
        );


    nebula *=
        nebula_density;


    // ========================================================
    // 9. STARS
    // ========================================================

    vec3 stars_1 =
        render_stars_layer(
            dir,
            star_density,
            twinkle_speed
        );


    vec3 stars_2 =
        render_stars_layer(
            dir,
            star_density * 0.5,
            twinkle_speed * 0.75
        );


    vec3 stars_total =
        (stars_1 +
        stars_2 * 1.2) *
        star_brightness;


    // ========================================================
    // 10. COMBINE
    // ========================================================

    vec3 final_color =
        nebula +
        stars_total;


    // ========================================================
    // 11. SATURATION
    // ========================================================

    float gray =
        dot(
            final_color,
            vec3(
                0.299,
                0.587,
                0.114
            )
        );


    vec3 saturated_color =
        mix(
            vec3(gray),
            final_color,
            saturation
        );


    // ========================================================
    // 12. OUTPUT
    // ========================================================

    ALBEDO =
        saturated_color;
}