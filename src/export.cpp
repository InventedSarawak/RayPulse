#include "export.h"
#include <OpenEXR/ImfRgbaFile.h>
#include <OpenEXR/ImfArray.h>
#include <vector>
#include <chrono>
#include <iomanip>
#include <sstream>
#include <cstdio>

void saveToEXR(GLuint texture, int width, int height, const char* filename) {
    std::vector<float> pixels(width * height * 4); // RGBA

    glBindTexture(GL_TEXTURE_2D, texture);
    glGetTexImage(GL_TEXTURE_2D, 0, GL_RGBA, GL_FLOAT, pixels.data());

    // Convert to OpenEXR format
    Imf::Array2D<Imf::Rgba> exrPixels(height, width);
    for (int y = 0; y < height; ++y) {
        for (int x = 0; x < width; ++x) {
            // OpenGL origin is bottom-left, OpenEXR is top-left
            int glIndex = ((height - 1 - y) * width + x) * 4;

            exrPixels[y][x].r = pixels[glIndex + 0];
            exrPixels[y][x].g = pixels[glIndex + 1];
            exrPixels[y][x].b = pixels[glIndex + 2];
            exrPixels[y][x].a = pixels[glIndex + 3];
        }
    }

    // Write to EXR file
    Imf::RgbaOutputFile file(filename, width, height, Imf::WRITE_RGBA);
    file.setFrameBuffer(&exrPixels[0][0], 1, width);
    file.writePixels(height);

    printf("Saved image to %s (%dx%d)\n", filename, width, height);
}

const char* generateTimestampedFilename(const char* prefix, const char* extension) {
    static char buffer[256];
    
    auto now = std::chrono::system_clock::now();
    auto time = std::chrono::system_clock::to_time_t(now);
    
    std::ostringstream filename;
    filename << prefix << "_" 
             << std::put_time(std::localtime(&time), "%Y%m%d_%H%M%S") 
             << extension;
    
    snprintf(buffer, sizeof(buffer), "%s", filename.str().c_str());
    return buffer;
}