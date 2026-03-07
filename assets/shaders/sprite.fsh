#version 330

in vec4 col_tint;
in vec3 tex_coord;
in float additive;
in float in_hueshift_pass;

uniform sampler2DArray tex;

out vec4 color;

float median(float r, float g, float b) {
    return max(min(r, g), min(max(r, g), b));
}

vec3 hueShift(vec3 col, float shift) {
    vec3 k = vec3(0.57735, 0.57735, 0.57735);
    float cosAngle = cos(shift);
    return col * cosAngle + cross(k, col) * sin(shift) + k * dot(k, col) * (1.0 - cosAngle);
}

void main() {
    vec4 in_color = texture(tex, tex_coord);

    color = in_color*col_tint;
    color.rgb = hueShift(color.rgb, in_hueshift_pass * 6.2831853);
    color.rgb *= color.a;
    color.a *= additive;
}