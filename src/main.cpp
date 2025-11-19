#include <cstdio>
#include <glad/gl.h>
#include <GLFW/glfw3.h>
#include "shader.h"
#include "texture.h"
#include "renderer.h"
#include "export.h"

#define INIT_WINDOW_WIDTH 800
#define INIT_WINDOW_HEIGHT 600

void framebuffer_size_callback(GLFWwindow* window, int width, int height);
void processInput(GLFWwindow* window, GLuint texture, int width, int height);

int main() {
    glfwInit();
    glfwWindowHint(GLFW_CONTEXT_VERSION_MAJOR, 4);
    glfwWindowHint(GLFW_CONTEXT_VERSION_MINOR, 6);
    glfwWindowHint(GLFW_OPENGL_PROFILE, GLFW_OPENGL_CORE_PROFILE);

    GLFWwindow* window = glfwCreateWindow(INIT_WINDOW_WIDTH, INIT_WINDOW_HEIGHT, 
                                          "Raypulse", nullptr, nullptr);
    if (window == nullptr) {
        printf("Failed to create GLFW window\n");
        glfwTerminate();
        return -1;
    }
    glfwMakeContextCurrent(window);
    glfwSetFramebufferSizeCallback(window, framebuffer_size_callback);

    const int version = gladLoadGL(glfwGetProcAddress);
    if (version == 0) {
        printf("Failed to initialize GLAD\n");
        return -1;
    }

    printf("OpenGL %d.%d\n", GLAD_VERSION_MAJOR(version), GLAD_VERSION_MINOR(version));

    // Load shaders from files
    GLuint renderProgram = createShaderProgramFromFiles("shaders/vertex.glsl", 
                                                        "shaders/fragment.glsl");
    GLuint computeProgram = createComputeProgramFromFile("shaders/compute.glsl");

    if (renderProgram == 0 || computeProgram == 0) {
        printf("Failed to create shader programs\n");
        return -1;
    }

    // Create texture and renderer
    RayTexture rayTexture = createRayTexture(INIT_WINDOW_WIDTH, INIT_WINDOW_HEIGHT);
    QuadRenderer quadRenderer;

    while (!glfwWindowShouldClose(window)) {
        int width, height;
        glfwGetFramebufferSize(window, &width, &height);
        
        processInput(window, rayTexture.id, width, height);

        // === Compute Pass: Generate ray traced image ===
        dispatchComputeShader(computeProgram, rayTexture.id, width, height);

        // === Render Pass: Display the texture on the quad ===
        glClear(GL_COLOR_BUFFER_BIT);
        glUseProgram(renderProgram);

        // Bind texture for sampling
        glActiveTexture(GL_TEXTURE0);
        glBindTexture(GL_TEXTURE_2D, rayTexture.id);

        // Draw the fullscreen quad
        quadRenderer.render();

        glfwSwapBuffers(window);
        glfwPollEvents();
    }

    // Cleanup
    destroyRayTexture(rayTexture);
    glDeleteProgram(renderProgram);
    glDeleteProgram(computeProgram);

    glfwTerminate();
    return 0;
}

void processInput(GLFWwindow* window, GLuint texture, int width, int height) {
    if (glfwGetKey(window, GLFW_KEY_ESCAPE) == GLFW_PRESS)
        glfwSetWindowShouldClose(window, 1);

    static bool sKeyWasPressed = false;
    bool sKeyIsPressed = glfwGetKey(window, GLFW_KEY_S) == GLFW_PRESS;
    if (sKeyIsPressed && !sKeyWasPressed) {
        const char* filename = generateTimestampedFilename("raypulse", ".exr");
        saveToEXR(texture, width, height, filename);
    }
    sKeyWasPressed = sKeyIsPressed;
}

void framebuffer_size_callback(GLFWwindow* window, int width, int height) {
    (void)window;
    glViewport(0, 0, width, height);
}