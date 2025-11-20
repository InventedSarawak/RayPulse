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

void QuadRenderer::render() const {
    glBindVertexArray(VAO);
    glDrawArrays(GL_TRIANGLES, 0, 6);
}

SceneBuffer::SceneBuffer() {
    glGenBuffers(1, &ssbo);
    glBindBuffer(GL_SHADER_STORAGE_BUFFER, ssbo);
    // Initialize with null data
    glBufferData(GL_SHADER_STORAGE_BUFFER, 0, nullptr, GL_DYNAMIC_DRAW);
    glBindBuffer(GL_SHADER_STORAGE_BUFFER, 0);
}

SceneBuffer::~SceneBuffer() {
    glDeleteBuffers(1, &ssbo);
}

void SceneBuffer::update(const std::vector<GPUObject>& objects) const {
    glBindBuffer(GL_SHADER_STORAGE_BUFFER, ssbo);
    // Re-allocate buffer to fit the vector size
    glBufferData(GL_SHADER_STORAGE_BUFFER, objects.size() * sizeof(GPUObject), objects.data(), GL_DYNAMIC_DRAW);
    glBindBuffer(GL_SHADER_STORAGE_BUFFER, 0);
}

void SceneBuffer::bind(GLuint bindingPoint) const {
    glBindBufferBase(GL_SHADER_STORAGE_BUFFER, bindingPoint, ssbo);
}

void dispatchComputeShader(const GLuint program, const GLuint texture, const RaytracerDimensions raytracer_dimensions,
    CameraParams camera_params, SkyParams sky_params, size_t objectCount, int samplesPerPixel) {
    glUseProgram(program);
    
    // Bind texture as image for writing
    glBindImageTexture(0, texture, 0, GL_FALSE, 0, GL_WRITE_ONLY, GL_RGBA32F);
    
    // Set uniforms
    glUniform2f(glGetUniformLocation(program, "resolution"), 
                static_cast<GLfloat>(raytracer_dimensions.width), static_cast<GLfloat>(raytracer_dimensions.height));

    glUniform3fv(glGetUniformLocation(program, "cameraOrigin"), 1, &camera_params.pos[0]);
    glUniform3fv(glGetUniformLocation(program, "cameraForward"), 1, &camera_params.forward[0]);
    glUniform3fv(glGetUniformLocation(program, "cameraRight"), 1, &camera_params.right[0]);
    glUniform3fv(glGetUniformLocation(program, "cameraUp"), 1, &camera_params.up[0]);
    glUniform1f(glGetUniformLocation(program, "cameraFOV"), camera_params.FOV);

    glUniform3fv(glGetUniformLocation(program, "skyColorTop"), 1, &sky_params.colorTop[0]);
    glUniform3fv(glGetUniformLocation(program, "skyColorBottom"), 1, &sky_params.colorBottom[0]);

    glUniform1i(glGetUniformLocation(program, "objectCount"), static_cast<GLint>(objectCount));

    glUniform1ui(glGetUniformLocation(program, "frameCount"), camera_params.frameCount);
    glUniform1i(glGetUniformLocation(program, "samplesPerPixel"), samplesPerPixel);

    // Dispatch compute shader
    // Calculate number of work groups needed: ceil to next multiple of 16
    glDispatchCompute((raytracer_dimensions.width + 15) / 16, (raytracer_dimensions.height + 15) / 16, 1);
    
    // Ensure compute shader has finished
    glMemoryBarrier(GL_SHADER_IMAGE_ACCESS_BARRIER_BIT);
}