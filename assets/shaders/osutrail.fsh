#version 330

uniform sampler2DArray tex;
uniform float layer;
uniform float alpha;
uniform float hue_shift;

in vec2 tex_coord;
in vec4 color_pass;

out vec4 color;

vec3 hueShift(vec3 col, float shift) {
    vec3 k = vec3(0.57735, 0.57735, 0.57735);
    float cosAngle = cos(shift);
    return col * cosAngle + cross(k, col) * sin(shift) + k * dot(k, col) * (1.0 - cosAngle);
}

void main() {
    vec4 in_color = texture(tex, vec3(tex_coord, layer));

    color = in_color * color_pass;
    color.rgb = hueShift(color.rgb, hue_shift * 6.2831853);
    color.a *= alpha;
}