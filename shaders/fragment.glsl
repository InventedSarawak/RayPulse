#version 410 core
out vec4 FragColor;
in vec2 TexCoord;

uniform sampler2D rayTexture;

void main()
{
    FragColor = texture(rayTexture, TexCoord);
}