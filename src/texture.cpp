#include "texture.h"

RayTexture createTexture(const int width, const int height, const GLenum internalFormat) {
    RayTexture tex;
    tex.width = width;
    tex.height = height;

    glGenTextures(1, &tex.id);
    glBindTexture(GL_TEXTURE_2D, tex.id);

    // We generally upload float data (GL_FLOAT), but the GPU stores it as 'internalFormat'
    glTexImage2D(GL_TEXTURE_2D, 0, internalFormat, width, height, 0, GL_RGBA, GL_FLOAT, nullptr);

    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    
    return tex;
}

void resizeTexture(RayTexture& texture, const int newWidth, const int newHeight, const GLenum internalFormat) {
    texture.width = newWidth;
    texture.height = newHeight;

    glBindTexture(GL_TEXTURE_2D, texture.id);
    glTexImage2D(GL_TEXTURE_2D, 0, internalFormat, newWidth, newHeight, 0, GL_RGBA, GL_FLOAT, nullptr);
}

void destroyTexture(RayTexture& texture) {
    glDeleteTextures(1, &texture.id);
    texture.id = 0;
}