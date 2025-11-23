#pragma once
#include <glad/gl.h>

struct RayTexture {
    GLuint id;
    int width;
    int height;
};

RayTexture createTexture(int width, int height, GLenum internalFormat);
void resizeTexture(RayTexture& texture, int newWidth, int newHeight, GLenum internalFormat);
void destroyTexture(RayTexture& texture);