#pragma once
#include <glad/gl.h>

struct RayTexture {
    GLuint id = 0;
    int width = 0;
    int height = 0;
};

RayTexture createTexture(int width, int height, GLenum internalFormat);
void resizeTexture(RayTexture& texture, int newWidth, int newHeight, GLenum internalFormat);
void destroyTexture(RayTexture& texture);