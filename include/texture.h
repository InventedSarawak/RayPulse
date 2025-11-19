#pragma once
#include <glad/gl.h>

struct RayTexture {
    GLuint id;
    int width;
    int height;
};

RayTexture createRayTexture(int width, int height);
void resizeRayTexture(RayTexture& texture, int newWidth, int newHeight);
void destroyRayTexture(RayTexture& texture);