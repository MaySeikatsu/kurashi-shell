#version 440
// The change of colour as a true cross-fade (components/ColorFade.qml): the window as it was (`old`, a picture taken
// before the new colours came in) and as it is (`source`, the window's own layer), mixed by `t`. A mix, not one drawn
// over the other: translucent parts — shadows, glass — neither double nor flash.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float t;
};
layout(binding = 1) uniform sampler2D source;
layout(binding = 2) uniform sampler2D old;
void main() {
    fragColor = mix(texture(old, qt_TexCoord0), texture(source, qt_TexCoord0), t) * qt_Opacity;
}
