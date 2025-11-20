#include <cstdio>
#include <glad/gl.h>
#include <GLFW/glfw3.h>
#include <glm/glm.hpp>
#include <glm/gtc/matrix_transform.hpp>
#include <glm/gtc/type_ptr.hpp>
#include "imgui.h"
#include "backends/imgui_impl_glfw.h"
#include "backends/imgui_impl_opengl3.h"
#include "shader.h"
#include "texture.h"
#include "renderer.h"
#include "export.h"

#define INIT_WINDOW_WIDTH 1280
#define INIT_WINDOW_HEIGHT 720

#define DEG_TO_RAD(deg) ((deg) * 3.14159265359f / 180.0f)

void calculateBasisFromEuler(const float pitch, const float yaw, const float roll,
                             glm::vec3& forward, glm::vec3& right, glm::vec3& up) {

    const float pitchRad = DEG_TO_RAD(pitch);
    const float yawRad = -DEG_TO_RAD(yaw);
    const float rollRad = -DEG_TO_RAD(roll);

    forward.x = cos(pitchRad) * sin(yawRad);
    forward.y = sin(pitchRad);
    forward.z = -cos(pitchRad) * cos(yawRad);
    forward = glm::normalize(forward);

    // Calculate right vector (cross product of world up and forward)
    constexpr auto worldUp = glm::vec3(0.0f, 1.0f, 0.0f);
    right = glm::normalize(glm::cross(worldUp, forward));

    // Calculate up vector (cross product of forward and right)
    up = glm::normalize(glm::cross(forward, right));

    // Apply roll rotation around the forward axis
    if (abs(rollRad) > 0.001f) {
        const float cosRoll = cos(rollRad);
        const float sinRoll = sin(rollRad);
        const glm::vec3 newRight = cosRoll * right + sinRoll * up;
        const glm::vec3 newUp = -sinRoll * right + cosRoll * up;
        right = newRight;
        up = newUp;
    }
}

void processInput(GLFWwindow* window);

// Helper to track current UI buffer size to detect window resizes
struct UIResolution {
    int width;
    int height;
};

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
    GLuint computeProgram = createComputeProgramFromBinary("./buildDir/main.spv");

    // Initial Raytracer Resolution
    RayTexture rayTexture = createRayTexture(INIT_WINDOW_WIDTH, INIT_WINDOW_HEIGHT);

    // Input variables for the GUI (initialized to start resolution)
    int targetRenderWidth = INIT_WINDOW_WIDTH;
    int targetRenderHeight = INIT_WINDOW_HEIGHT;

    QuadRenderer quadRenderer;

    SceneBuffer sceneBuffer;
    std::vector<GPUObject> objects;

    objects.push_back(makeSphere(glm::vec3(0.0f, 0.0f, -1.0f), 0.5f));      // Center
    objects.push_back(makeSphere(glm::vec3(0.0f, -100.5f, -1.0f), 100.0f)); // The Floor
    objects.push_back(makeSphere(glm::vec3(-1.0f, 0.0f, -1.0f), 0.5f));     // Left

    sceneBuffer.update(objects);
    sceneBuffer.bind(1);

    // Create UI Cache (Tracks Window Size)
    GLuint uiFBO = 0;
    GLuint uiTexture = 0;
    UIResolution currentUIRes = {0, 0}; // Force initial creation

    // Profiling & Timers
    GLuint timeQuery;
    glGenQueries(1, &timeQuery);
    GLuint64 elapsedNanoseconds = 0;

    // Scene Params
    bool isRendering = true;
    auto cameraPos = glm::vec3{0.0f, 0.0f, 0.0f};
    auto cameraRot = glm::vec3{0.0f, 0.0f, 0.0f};

    CameraParams camera_params = {cameraPos, glm::vec3{0.0f, 0.0f, 0.0f}, glm::vec3{0.0f, 0.0f, 0.0f}, glm::vec3{0.0f, 0.0f, 0.0f}, 90.0f};
    calculateBasisFromEuler(cameraRot[0], cameraRot[1], cameraRot[2],
                           camera_params.forward, camera_params.right, camera_params.up);

    SkyParams sky_params = {glm::vec3{0.5, 0.7, 1.0}, glm::vec3{0.98, 0.98, 0.98}};

    float spherePos[3] = {0.0f, 0.0f, -1.0f};
    float sphereRadius = 0.5f;

    // Dynamic UI Interval based on Monitor Hz
    double uiUpdateInterval = 1.0 / static_cast<double>(monitorRefreshRate);
    double lastUITime = 0.0;

    while (!glfwWindowShouldClose(window)) {
        double currentTime = glfwGetTime();

        // Get Window/Viewport dimensions (for Display and UI)
        int winWidth, winHeight;
        glfwGetFramebufferSize(window, &winWidth, &winHeight);

        // Prepare Raytracer dimensions (for Compute Shader)
        // Note: We now use rayTexture.width/height, NOT winWidth/winHeight
        RaytracerDimensions raytracer_dimensions = {rayTexture.width, rayTexture.height};

        // Handle UI/Window Resizing
        // (We only resize the UI buffer when window changes, NOT the rayTexture)
        if (winWidth != currentUIRes.width || winHeight != currentUIRes.height) {
            currentUIRes.width = winWidth;
            currentUIRes.height = winHeight;
            createUIFramebuffer(winWidth, winHeight, &uiFBO, &uiTexture);
        }

        if (isRendering) {
            glBeginQuery(GL_TIME_ELAPSED, timeQuery);
            dispatchComputeShader(computeProgram, rayTexture.id, raytracer_dimensions,
                camera_params, sky_params, objects.size());
            glEndQuery(GL_TIME_ELAPSED);
            glGetQueryObjectui64v(timeQuery, GL_QUERY_RESULT, &elapsedNanoseconds);
        }

        // 1. Render the Raytraced Texture to the default framebuffer (The Screen)
        glBindFramebuffer(GL_FRAMEBUFFER, 0);
        glViewport(0, 0, winWidth, winHeight); // Stretch to fill window
        glDisable(GL_BLEND);
        glUseProgram(renderProgram);
        glActiveTexture(GL_TEXTURE0);
        glBindTexture(GL_TEXTURE_2D, rayTexture.id);
        quadRenderer.render();

        // 2. Render UI
        if (currentTime - lastUITime >= uiUpdateInterval) {
            lastUITime = currentTime;

            // Draw UI into FBO
            glBindFramebuffer(GL_FRAMEBUFFER, uiFBO);
            glViewport(0, 0, winWidth, winHeight);
            glClearColor(0, 0, 0, 0);
            glClear(GL_COLOR_BUFFER_BIT);

            ImGui_ImplOpenGL3_NewFrame();
            ImGui_ImplGlfw_NewFrame();
            ImGui::NewFrame();

            ImGui::Begin("Raypulse Controls");

            float gpuTimeMs = elapsedNanoseconds / 1000000.0f;
            ImGui::TextColored(ImVec4(0,1,0,1), "Raytrace Speed: %.0f FPS", 1000.0f / (gpuTimeMs + 0.0001f));
            ImGui::Text("Render Res: %dx%d", rayTexture.width, rayTexture.height);
            ImGui::Text("Window Res: %dx%d", winWidth, winHeight);

            ImGui::Separator();
            if (ImGui::CollapsingHeader("Resolution Settings", ImGuiTreeNodeFlags_DefaultOpen)) {
                ImGui::InputInt("Width", &targetRenderWidth);
                ImGui::InputInt("Height", &targetRenderHeight);

                if (ImGui::Button("Set Resolution")) {
                    if (targetRenderWidth > 0 && targetRenderHeight > 0) {
                        resizeRayTexture(rayTexture, targetRenderWidth, targetRenderHeight);
                        // Trigger a re-render immediately
                        dispatchComputeShader(computeProgram, rayTexture.id,
                            {targetRenderWidth, targetRenderHeight},
                            camera_params, sky_params, objects.size());
                    }
                }
            }

            ImGui::Separator();
            // Camera controls
            if (ImGui::CollapsingHeader("Camera", ImGuiTreeNodeFlags_DefaultOpen)) {
                ImGui::DragFloat3("Position", glm::value_ptr(cameraPos), 0.1f);

                const float prevRot[3] = {cameraRot[0], cameraRot[1], cameraRot[2]};

                ImGui::SliderFloat("Pitch (X)", &cameraRot[0], -90.0f, 90.0f, "%.1f°");
                ImGui::SliderFloat("Yaw (Y)", &cameraRot[1], -180.0f, 180.0f, "%.1f°");
                ImGui::SliderFloat("Roll (Z)", &cameraRot[2], -180.0f, 180.0f, "%.1f°");

                // Check if rotation changed
                const bool rotationChanged = (prevRot[0] != cameraRot[0]) ||
                                      (prevRot[1] != cameraRot[1]) ||
                                      (prevRot[2] != cameraRot[2]);

                // Recalculate basis vectors only if rotation changed
                if (rotationChanged) {
                    calculateBasisFromEuler(cameraRot[0], cameraRot[1], cameraRot[2],
                                          camera_params.forward, camera_params.right, camera_params.up);
                }

                ImGui::SliderFloat("FOV", &camera_params.FOV, 20.0f, 150.0f, "%.1f°");
            }

            // Sphere controls
            if (ImGui::CollapsingHeader("Sphere", ImGuiTreeNodeFlags_DefaultOpen)) {
                ImGui::DragFloat3("Center", spherePos, 0.1f);
                ImGui::DragFloat("Radius", &sphereRadius, 0.1f, 0.0f, 2.0f);
            }

            // Sky controls
            if (ImGui::CollapsingHeader("Sky Colors", ImGuiTreeNodeFlags_DefaultOpen)) {
                ImGui::ColorEdit3("Bottom Color", glm::value_ptr(sky_params.colorBottom));
                ImGui::ColorEdit3("Top Color", glm::value_ptr(sky_params.colorTop));
            }


            ImGui::Separator();
            ImGui::Checkbox("Real-time Rendering", &isRendering);
            if (ImGui::Button("Save .exr")) {
                const char* filename = generateTimestampedFilename("raypulse", ".exr");
                // Use actual RayTexture dimensions, not window dimensions
                saveToEXR(rayTexture.id, rayTexture.width, rayTexture.height, filename);
            }
            ImGui::End();

            ImGui::Render();
            ImGui_ImplOpenGL3_RenderDrawData(ImGui::GetDrawData());
        }

        // Composite UI on top
        glBindFramebuffer(GL_FRAMEBUFFER, 0);
        glViewport(0, 0, winWidth, winHeight);
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