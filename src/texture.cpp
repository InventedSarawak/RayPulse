#include "texture.h"

RayTexture createRayTexture(int width, int height) {
    RayTexture tex;
    tex.width = width;
    tex.height = height;
    
    glGenTextures(1, &tex.id);
    glBindTexture(GL_TEXTURE_2D, tex.id);
    
    // Allocate storage - RGBA with 32-bit floats per channel
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA32F, width, height, 0, GL_RGBA, GL_FLOAT, nullptr);
    
    // Set texture parameters
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    
    return tex;
}

void resizeRayTexture(RayTexture& texture, int newWidth, int newHeight) {
    texture.width = newWidth;
    texture.height = newHeight;
    
    glBindTexture(GL_TEXTURE_2D, texture.id);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA32F, newWidth, newHeight, 0, GL_RGBA, GL_FLOAT, nullptr);
}

void destroyRayTexture(RayTexture& texture) {
    glDeleteTextures(1, &texture.id);
    texture.id = 0;
}