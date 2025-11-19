#pragma once
#include <glad/gl.h>
#include <glm/glm.hpp>

struct QuadVertex {
    glm::vec2 position;
    glm::vec2 texCoord;
};

class QuadRenderer {
public:
    QuadRenderer();
    ~QuadRenderer();
    
    void render();
    GLuint getVAO() const { return VAO; }
    
private:
    GLuint VAO;
    GLuint VBO;
};

void dispatchComputeShader(GLuint program, GLuint texture, int width, int height);