#include "renderer.h"

QuadRenderer::QuadRenderer() {
    QuadVertex quadVertices[] = {
        // First triangle
        {{-1.0f, 1.0f}, {0.0f, 1.0f}},   // Top-left
        {{-1.0f, -1.0f}, {0.0f, 0.0f}},  // Bottom-left
        {{1.0f, -1.0f}, {1.0f, 0.0f}},   // Bottom-right
        // Second triangle
        {{-1.0f, 1.0f}, {0.0f, 1.0f}},   // Top-left
        {{1.0f, -1.0f}, {1.0f, 0.0f}},   // Bottom-right
        {{1.0f, 1.0f}, {1.0f, 1.0f}}     // Top-right
    };
    
    glGenVertexArrays(1, &VAO);
    glGenBuffers(1, &VBO);
    
    glBindVertexArray(VAO);
    glBindBuffer(GL_ARRAY_BUFFER, VBO);
    glBufferData(GL_ARRAY_BUFFER, sizeof(quadVertices), quadVertices, GL_STATIC_DRAW);
    
    // Position attribute (location = 0)
    glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, sizeof(QuadVertex),
                          reinterpret_cast<void*>(offsetof(QuadVertex, position)));
    glEnableVertexAttribArray(0);
    
    // TexCoord attribute (location = 1)
    glVertexAttribPointer(1, 2, GL_FLOAT, GL_FALSE, sizeof(QuadVertex),
                          reinterpret_cast<void*>(offsetof(QuadVertex, texCoord)));
    glEnableVertexAttribArray(1);
}

QuadRenderer::~QuadRenderer() {
    glDeleteVertexArrays(1, &VAO);
    glDeleteBuffers(1, &VBO);
}

void QuadRenderer::render() {
    glBindVertexArray(VAO);
    glDrawArrays(GL_TRIANGLES, 0, 6);
}

void dispatchComputeShader(GLuint program, GLuint texture, int width, int height) {
    glUseProgram(program);
    
    // Bind texture as image for writing
    glBindImageTexture(0, texture, 0, GL_FALSE, 0, GL_WRITE_ONLY, GL_RGBA32F);
    
    // Set resolution uniform
    glUniform2f(glGetUniformLocation(program, "resolution"), 
                static_cast<GLfloat>(width), static_cast<GLfloat>(height));
    
    // Dispatch compute shader
    // Calculate number of work groups needed: ceil to next multiple of 16
    glDispatchCompute((width + 15) / 16, (height + 15) / 16, 1);
    
    // Ensure compute shader has finished
    glMemoryBarrier(GL_SHADER_IMAGE_ACCESS_BARRIER_BIT);
}