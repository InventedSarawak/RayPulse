#version 460 core
out vec4 FragColor;
in vec2 TexCoord;

uniform sampler2D rayTexture;
uniform vec2 renderResolution;
uniform vec2 windowResolution;
uniform sampler2D bloomTexture;
uniform bool bloomEnabled;
uniform float bloomIntensity;

void main()
{
    float renderAspect = renderResolution.x / renderResolution.y;
    float windowAspect = windowResolution.x / windowResolution.y;

    vec2 uv = TexCoord;

    if (renderAspect > windowAspect) {
        // Image is wider than window (Letterbox - Bars on Top/Bottom)
        float scale = windowAspect / renderAspect;

        uv.y = (uv.y - 0.5) / scale + 0.5;

        if (uv.y < 0.0 || uv.y > 1.0) {
            FragColor = vec4(0.0, 0.0, 0.0, 1.0);
            return;
        }
    }
    else if (renderAspect < windowAspect) {
        // Image is taller than window (Pillarbox - Bars on Left/Right)
        float scale = renderAspect / windowAspect;

        uv.x = (uv.x - 0.5) / scale + 0.5;

        if (uv.x < 0.0 || uv.x > 1.0) {
            FragColor = vec4(0.0, 0.0, 0.0, 1.0);
            return;
        }
    }

    vec4 color = texture(rayTexture, uv);
    if (bloomEnabled) {
        vec3 bloom = texture(bloomTexture, uv).rgb;
        color.rgb += bloom * bloomIntensity;
    }
    FragColor = color;
}