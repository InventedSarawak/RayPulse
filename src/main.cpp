#include <cstdio>
#include <glad/gl.h>
#include <GLFW/glfw3.h>
#include "imgui.h"
#include "backends/imgui_impl_glfw.h"
#include "backends/imgui_impl_opengl3.h"
#include "shader.h"
#include "texture.h"
#include "renderer.h"
#include "export.h"

#define INIT_WINDOW_WIDTH 1280
#define INIT_WINDOW_HEIGHT 720

void processInput(GLFWwindow* window);

void createUIFramebuffer(int width, int height, GLuint* fbo, GLuint* tex) {
    if (*fbo) glDeleteFramebuffers(1, fbo);
    if (*tex) glDeleteTextures(1, tex);

    glGenFramebuffers(1, fbo);
    glBindFramebuffer(GL_FRAMEBUFFER, *fbo);

    glGenTextures(1, tex);
    glBindTexture(GL_TEXTURE_2D, *tex);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, width, height, 0, GL_RGBA, GL_UNSIGNED_BYTE, nullptr);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);

    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, *tex, 0);
    glBindFramebuffer(GL_FRAMEBUFFER, 0);
}

int main() {
    // 1. Initialize GLFW
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

    glfwSwapInterval(0);

    // 2. Initialize GLAD
    const int version = gladLoadGL(glfwGetProcAddress);
    if (version == 0) return -1;

    // 3. Get Monitor Refresh Rate
    GLFWmonitor* primaryMonitor = glfwGetPrimaryMonitor();
    const GLFWvidmode* videoMode = glfwGetVideoMode(primaryMonitor);
    int monitorRefreshRate = videoMode->refreshRate;
    if (monitorRefreshRate <= 1) monitorRefreshRate = 60;

    // 4. Initialize ImGui
    IMGUI_CHECKVERSION();
    ImGui::CreateContext();
    ImGuiIO& io = ImGui::GetIO(); (void)io;
    ImGui::StyleColorsDark();
    ImGui_ImplGlfw_InitForOpenGL(window, true);
    ImGui_ImplOpenGL3_Init("#version 460");

    // 5. Create Resources
    GLuint renderProgram = createShaderProgramFromFiles("shaders/vertex.glsl", "shaders/fragment.glsl");
    GLuint computeProgram = createComputeProgramFromFile("shaders/compute.glsl");
    RayTexture rayTexture = createRayTexture(INIT_WINDOW_WIDTH, INIT_WINDOW_HEIGHT);
    QuadRenderer quadRenderer;

    // Create UI Cache
    GLuint uiFBO = 0;
    GLuint uiTexture = 0;
    createUIFramebuffer(INIT_WINDOW_WIDTH, INIT_WINDOW_HEIGHT, &uiFBO, &uiTexture);

    // Profiling & Timers
    GLuint timeQuery;
    glGenQueries(1, &timeQuery);
    GLuint64 elapsedNanoseconds = 0;
    bool isRendering = true;

    // Dynamic UI Interval based on Monitor Hz
    double uiUpdateInterval = 1.0 / (double)monitorRefreshRate;
    double lastUITime = 0.0;

    while (!glfwWindowShouldClose(window)) {
        double currentTime = glfwGetTime();
        int width, height;
        glfwGetFramebufferSize(window, &width, &height);

        // Handle Resizing directly in the loop
        if (width != rayTexture.width || height != rayTexture.height) {
            resizeRayTexture(rayTexture, width, height);
            createUIFramebuffer(width, height, &uiFBO, &uiTexture);
            dispatchComputeShader(computeProgram, rayTexture.id, width, height);
        }

        if (isRendering) {
            glBeginQuery(GL_TIME_ELAPSED, timeQuery);
            dispatchComputeShader(computeProgram, rayTexture.id, width, height);
            glEndQuery(GL_TIME_ELAPSED);
            glGetQueryObjectui64v(timeQuery, GL_QUERY_RESULT, &elapsedNanoseconds);
        }


        glBindFramebuffer(GL_FRAMEBUFFER, 0);
        glViewport(0, 0, width, height);
        glDisable(GL_BLEND);
        glUseProgram(renderProgram);
        glActiveTexture(GL_TEXTURE0);
        glBindTexture(GL_TEXTURE_2D, rayTexture.id);
        quadRenderer.render();


        if (currentTime - lastUITime >= uiUpdateInterval) {
            lastUITime = currentTime;

            // Draw UI into FBO
            glBindFramebuffer(GL_FRAMEBUFFER, uiFBO);
            glViewport(0, 0, width, height);
            glClearColor(0, 0, 0, 0);
            glClear(GL_COLOR_BUFFER_BIT);

            ImGui_ImplOpenGL3_NewFrame();
            ImGui_ImplGlfw_NewFrame();
            ImGui::NewFrame();

            ImGui::Begin("Raypulse Controls");

            float gpuTimeMs = elapsedNanoseconds / 1000000.0f;
            // This shows the real speed of the Raytracer loop
            ImGui::TextColored(ImVec4(0,1,0,1), "Raytrace Speed: %.0f FPS", 1000.0f / (gpuTimeMs + 0.0001f));

            ImGui::Separator();
            ImGui::Checkbox("Real-time Rendering", &isRendering);
            if (ImGui::Button("Save .exr")) {
                const char* filename = generateTimestampedFilename("raypulse", ".exr");
                saveToEXR(rayTexture.id, width, height, filename);
            }
            ImGui::End();

            ImGui::Render();
            ImGui_ImplOpenGL3_RenderDrawData(ImGui::GetDrawData());
        }

        // Composite UI on top
        glBindFramebuffer(GL_FRAMEBUFFER, 0);
        glViewport(0, 0, width, height);
        glEnable(GL_BLEND);
        glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);

        glUseProgram(renderProgram);
        glActiveTexture(GL_TEXTURE0);
        glBindTexture(GL_TEXTURE_2D, uiTexture);
        quadRenderer.render();

        processInput(window);
        glfwSwapBuffers(window); // Returns immediately (Interval 0)
        glfwPollEvents();
    }

    // Cleanup
    glDeleteFramebuffers(1, &uiFBO);
    glDeleteTextures(1, &uiTexture);
    ImGui_ImplOpenGL3_Shutdown();
    ImGui_ImplGlfw_Shutdown();
    ImGui::DestroyContext();
    destroyRayTexture(rayTexture);
    glDeleteProgram(renderProgram);
    glDeleteProgram(computeProgram);
    glDeleteQueries(1, &timeQuery);
    glfwTerminate();
    return 0;
}

void processInput(GLFWwindow* window) {
    if (ImGui::GetIO().WantCaptureKeyboard || ImGui::GetIO().WantCaptureMouse) return;
    if (glfwGetKey(window, GLFW_KEY_ESCAPE) == GLFW_PRESS) glfwSetWindowShouldClose(window, 1);
}