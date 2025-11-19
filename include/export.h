#pragma once
#include <glad/gl.h>

void saveToEXR(GLuint texture, int width, int height, const char* filename);
const char* generateTimestampedFilename(const char* prefix, const char* extension);