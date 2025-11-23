#version 460 core

out vec4 FragColor;
in vec2 TexCoord;

uniform sampler2D sourceTexture;
uniform float bloomThreshold;
uniform float bloomKnee;

void main() {
    vec3 color = texture(sourceTexture, TexCoord).rgb;

    float brightness = max(max(abs(color.r), abs(color.g)), abs(color.b));

    // Standard soft-knee curve calculation
    float softKnee = max(bloomThreshold * bloomKnee, 0.0);
    float kneeStart = bloomThreshold - softKnee;
    float kneeEnd = bloomThreshold + softKnee;

    // Calculate contribution factor (0.0 to 1.0+)
    float contribution = 0.0;

    // Hard cutoff check
    if (brightness > bloomThreshold) {
        contribution = brightness - bloomThreshold;
    }
    // Soft knee check
    else if (brightness > kneeStart && softKnee > 0.0) {
        float soft = brightness - kneeStart;
        contribution = (soft * soft) / (4.0 * softKnee);
    }

    float bloomFactor = contribution / max(brightness, 1e-5);

    vec3 bloomColor = color * bloomFactor;
    FragColor = vec4(bloomColor, 1.0);
}