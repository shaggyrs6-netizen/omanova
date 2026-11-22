// Reproject the existing Blue Marble texture onto the same observer-centred
// orthographic disc used for ground tracks in OrbitGlobe.qml.
// Bake with: qsb --qt6 --qsbversion 64 -o earth-disc.frag.qsb earth-disc.frag
#version 440

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float longitude;
    float latitude;
};

layout(binding = 1) uniform sampler2D earthTexture;

void main()
{
    const float pi = 3.14159265359;
    vec2 point = (qt_TexCoord0 - 0.5) * vec2(2.0, -2.0);
    float radius = length(point);
    if (radius > 1.0) {
        fragColor = vec4(0.0);
        return;
    }

    float z = sqrt(max(0.0, 1.0 - dot(point, point)));
    float sl = sin(latitude);
    float cl = cos(latitude);
    float phi = asin(clamp(point.y * cl + z * sl, -1.0, 1.0));
    float lambda = longitude + atan(point.x, z * cl - point.y * sl);
    vec2 uv = vec2(fract(lambda / (2.0 * pi) + 0.5), 0.5 - phi / pi);
    vec3 earth = texture(earthTexture, uv).rgb;
    float light = clamp(dot(vec3(point, z), vec3(-0.48, 0.32, 0.76)) * 1.24, 0.32, 1.08);
    vec3 atmosphere = vec3(0.10, 0.34, 0.62) * pow(1.0 - z, 3.6);
    float alpha = (1.0 - smoothstep(0.987, 1.0, radius)) * qt_Opacity;
    fragColor = vec4((earth * light + atmosphere) * alpha, alpha);
}
