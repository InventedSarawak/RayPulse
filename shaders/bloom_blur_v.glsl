#version 460 core
out vec4 FragColor;
in vec2 TexCoord;

uniform sampler2D sourceTexture;
uniform vec2 texelSize;
uniform float weights[5];

void main() {
    vec2 uv = TexCoord;
    vec3 result = texture(sourceTexture, uv).rgb * weights[0];
    for (int i = 1; i < 5; ++i) {
        result += texture(sourceTexture, uv + vec2(0.0, texelSize.y * float(i))).rgb * weights[i];
        result += texture(sourceTexture, uv - vec2(0.0, texelSize.y * float(i))).rgb * weights[i];
    }
    FragColor = vec4(result, 1.0);
}

