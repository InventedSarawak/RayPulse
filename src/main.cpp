#define NOMINMAX

#include <cstdio>
#include <cstdint>
#include <glad/gl.h>
#include <GLFW/glfw3.h>
#include <glm/glm.hpp>
#include <glm/gtc/matrix_transform.hpp>
#include <glm/gtc/type_ptr.hpp>
#include <vector>
#include <array>
#include <algorithm>
#include <cmath>
#include <iostream>

#include "imgui.h"
#include "backends/imgui_impl_glfw.h"
#include "backends/imgui_impl_opengl3.h"
#include "shader.h"
#include "texture.h"
#include "renderer.h"
#include "export.h"
#include "MaterialFactory.h"
#include "paths.h"
#include "SceneBuilder.h"
#include "SceneLoader.h"

#define INIT_WINDOW_WIDTH 1600
#define INIT_WINDOW_HEIGHT 900

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

    constexpr auto worldUp = glm::vec3(0.0f, 1.0f, 0.0f);
    right = glm::normalize(glm::cross(worldUp, forward));
    up = glm::normalize(glm::cross(forward, right));

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

struct UIResolution{
    int width;
    int height;
};

void createUIFramebuffer(const int width, const int height, GLuint* fbo, GLuint* tex);

struct BloomPipeline {
    GLuint extractProgram = 0;
    GLuint blurHProgram = 0;
    GLuint blurVProgram = 0;
    RayTexture ping;
    RayTexture pong;
};

void destroyBloomPipeline(BloomPipeline& pipeline) {
    if (pipeline.extractProgram) glDeleteProgram(pipeline.extractProgram);
    if (pipeline.blurHProgram) glDeleteProgram(pipeline.blurHProgram);
    if (pipeline.blurVProgram) glDeleteProgram(pipeline.blurVProgram);
    if (pipeline.ping.id) destroyTexture(pipeline.ping);
    if (pipeline.pong.id) destroyTexture(pipeline.pong);
    pipeline = {};
}

GLuint loadBloomShader(const char* fragPath) {
    GLuint vertexShader = compileShaderFromFile(GL_VERTEX_SHADER, "shaders/vertex.glsl");
    GLuint fragmentShader = compileShaderFromFile(GL_FRAGMENT_SHADER, fragPath);
    if (vertexShader == 0 || fragmentShader == 0) {
        if (vertexShader) glDeleteShader(vertexShader);
        if (fragmentShader) glDeleteShader(fragmentShader);
        return 0;
    }
    GLuint program = glCreateProgram();
    glAttachShader(program, vertexShader);
    glAttachShader(program, fragmentShader);
    glLinkProgram(program);
    GLint success;
    glGetProgramiv(program, GL_LINK_STATUS, &success);
    if (!success) {
        char infoLog[512];
        glGetProgramInfoLog(program, 512, nullptr, infoLog);
        printf("Bloom shader link failed: %s\n", infoLog);
    }
    glDeleteShader(vertexShader);
    glDeleteShader(fragmentShader);
    return program;
}

void ensureBloomTextures(BloomPipeline& pipeline, int width, int height) {
    if (pipeline.ping.id == 0) pipeline.ping = createTexture(width, height, GL_RGBA16F);
    if (pipeline.pong.id == 0) pipeline.pong = createTexture(width, height, GL_RGBA16F);
    if (pipeline.ping.width != width || pipeline.ping.height != height)
        resizeTexture(pipeline.ping, width, height, GL_RGBA16F);
    if (pipeline.pong.width != width || pipeline.pong.height != height)
        resizeTexture(pipeline.pong, width, height, GL_RGBA16F);
}

void initBloomPipeline(BloomPipeline& pipeline) {
    pipeline.extractProgram = loadBloomShader("shaders/bloom_extract.glsl");
    pipeline.blurHProgram = loadBloomShader("shaders/bloom_blur_h.glsl");
    pipeline.blurVProgram = loadBloomShader("shaders/bloom_blur_v.glsl");
}

struct BloomFrameResult {
    GLuint textureId = 0;
    int width = 0;
    int height = 0;
};

std::array<float, 5> buildGaussianWeights(float sigma) {
    std::array<float, 5> weights{};
    float sum = 0.0f;
    for (int i = 0; i < 5; ++i) {
        float x = static_cast<float>(i);
        float weight = std::exp(-(x * x) / (2.0f * sigma * sigma));
        weights[i] = weight;
        sum += (i == 0) ? weight : 2.0f * weight;
    }
    for (float& weight : weights) {
        weight /= sum;
    }
    return weights;
}

BloomFrameResult applyBloom(const BloomConfig& config, BloomPipeline& pipeline, GLuint& bloomFBO,
                             GLuint sourceTexture, int sourceWidth, int sourceHeight,
                             const QuadRenderer& quadRenderer) {
    BloomFrameResult result{};
    if (!config.enabled || sourceTexture == 0) return result;
    if (pipeline.extractProgram == 0 || pipeline.blurHProgram == 0 || pipeline.blurVProgram == 0) return result;

    const float downscale = std::clamp(config.downscale, 0.1f, 1.0f);
    const int targetWidth = std::max(1, static_cast<int>(sourceWidth * downscale));
    const int targetHeight = std::max(1, static_cast<int>(sourceHeight * downscale));
    ensureBloomTextures(pipeline, targetWidth, targetHeight);

    if (bloomFBO == 0) {
        glGenFramebuffers(1, &bloomFBO);
    }

    glDisable(GL_BLEND);
    glBindFramebuffer(GL_FRAMEBUFFER, bloomFBO);
    glViewport(0, 0, targetWidth, targetHeight);
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, pipeline.ping.id, 0);
    glDrawBuffer(GL_COLOR_ATTACHMENT0);
    glClearColor(0.0f, 0.0f, 0.0f, 0.0f);
    glClear(GL_COLOR_BUFFER_BIT);

    glUseProgram(pipeline.extractProgram);
    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_2D, sourceTexture);
    glUniform1i(glGetUniformLocation(pipeline.extractProgram, "sourceTexture"), 0);
    glUniform1f(glGetUniformLocation(pipeline.extractProgram, "bloomThreshold"), std::max(config.threshold, 0.0f));
    glUniform1f(glGetUniformLocation(pipeline.extractProgram, "bloomKnee"), std::clamp(config.knee, 0.0f, 1.0f));
    quadRenderer.render();

    const auto weights = buildGaussianWeights(2.5f);
    const int passes = std::max(1, config.iterations);
    for (int i = 0; i < passes; ++i) {
        glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, pipeline.pong.id, 0);
        glUseProgram(pipeline.blurHProgram);
        glUniform2f(glGetUniformLocation(pipeline.blurHProgram, "texelSize"), 1.0f / targetWidth, 1.0f / targetHeight);
        glUniform1fv(glGetUniformLocation(pipeline.blurHProgram, "weights"), static_cast<GLsizei>(weights.size()), weights.data());
        glUniform1i(glGetUniformLocation(pipeline.blurHProgram, "sourceTexture"), 0);
        glActiveTexture(GL_TEXTURE0);
        glBindTexture(GL_TEXTURE_2D, pipeline.ping.id);
        quadRenderer.render();

        glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, pipeline.ping.id, 0);
        glUseProgram(pipeline.blurVProgram);
        glUniform2f(glGetUniformLocation(pipeline.blurVProgram, "texelSize"), 1.0f / targetWidth, 1.0f / targetHeight);
        glUniform1fv(glGetUniformLocation(pipeline.blurVProgram, "weights"), static_cast<GLsizei>(weights.size()), weights.data());
        glUniform1i(glGetUniformLocation(pipeline.blurVProgram, "sourceTexture"), 0);
        glActiveTexture(GL_TEXTURE0);
        glBindTexture(GL_TEXTURE_2D, pipeline.pong.id);
        quadRenderer.render();
    }

    glBindFramebuffer(GL_FRAMEBUFFER, 0);
    result.textureId = pipeline.ping.id;
    result.width = targetWidth;
    result.height = targetHeight;
    return result;
}

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
    glfwSwapInterval(0);

    const int version = gladLoadGL(glfwGetProcAddress);
    if (version == 0) return -1;

    GLFWmonitor* primaryMonitor = glfwGetPrimaryMonitor();
    const GLFWvidmode* videoMode = glfwGetVideoMode(primaryMonitor);
    int monitorRefreshRate = videoMode->refreshRate;
    if (monitorRefreshRate <= 1) monitorRefreshRate = 60;

    IMGUI_CHECKVERSION();
    ImGui::CreateContext();
    ImGuiIO& io = ImGui::GetIO();
    (void)io;
    ImGui::StyleColorsDark();
    ImGui_ImplGlfw_InitForOpenGL(window, true);
    ImGui_ImplOpenGL3_Init("#version 460");

    // Resources
    GLuint renderProgram = createShaderProgramFromFiles("shaders/vertex.glsl", "shaders/fragment.glsl");
    std::string shaderPath = getResourcePath("main.spv");
    GLuint computeProgram = createComputeProgramFromBinary(shaderPath.c_str());

    auto sceneConfigOpt = SceneLoader::loadFromFile("./scenes/candles.json");
    if (!sceneConfigOpt.has_value()) {
        printf("ERROR: Failed to load scene: %s\n", SceneLoader::getLastError().c_str());
        glfwTerminate();
        return -1;
    }

    SceneConfig sceneConfig = sceneConfigOpt.value();
    std::string validationError;
    if (!SceneBuilder::validate(sceneConfig, validationError)) {
        printf("ERROR: Scene validation failed: %s\n", validationError.c_str());
        glfwTerminate();
        return -1;
    }

    SceneData sceneData = SceneBuilder::buildScene(sceneConfig);

    std::cout << "\n=== RAW MEMORY DUMP OF MATERIAL 5 ===" << std::endl;
    if (sceneData.materials.size() > 5) {
        const GPUMaterial& mat = sceneData.materials[5];
        const unsigned char* bytes = reinterpret_cast<const unsigned char*>(&mat);

        std::cout << "Material 5 address: " << (void*)&mat << std::endl;
        std::cout << "Emission field address: " << (void*)&mat.emission << std::endl;
        std::cout << "EmissionStrength field address: " << (void*)&mat.emissionStrength << std::endl;

        std::cout << "\nFirst 48 bytes (covers albedo, emission, emissionStrength, roughness):" << std::endl;
        for (int i = 0; i < 48; i += 4) {
            float value;
            std::memcpy(&value, &bytes[i], sizeof(float));

            std::cout << "  Offset " << std::setw(2) << i << ": ";
            for (int j = 0; j < 4; j++) {
                std::cout << std::hex << std::setw(2) << std::setfill('0')
                          << (int)bytes[i + j] << " ";
            }
            std::cout << std::dec << " = " << std::setw(10) << value;

            if (i == 0) std::cout << " (albedo.x)";
            else if (i == 16) std::cout << " (emission.x) ← should be 1.0";
            else if (i == 20) std::cout << " (emission.y) ← should be 1.0";
            else if (i == 24) std::cout << " (emission.z) ← should be 1.0";
            else if (i == 28) std::cout << " (emissionStrength) ← should be 15.0";
            else if (i == 32) std::cout << " (roughness) ← should be 1.0";

            std::cout << std::endl;
        }
    }
    std::cout << "======================================\n" << std::endl;

    SceneBuffer sceneBuffer;
    MaterialBuffer materialBuffer;
    LightBuffer lightBuffer;

    sceneBuffer.update(sceneData.objects);
    sceneBuffer.bind(1);
    materialBuffer.update(sceneData.materials);
    materialBuffer.bind(2);
    lightBuffer.update(sceneData.lightIndices);
    lightBuffer.bind(3);

    auto cameraRot = glm::vec3{0.0f, 0.0f, 0.0f};
    CameraParams camera_params = {
        sceneConfig.camera.position,
        glm::vec3(0.0f), glm::vec3(0.0f), glm::vec3(0.0f),
        sceneConfig.camera.fov,
        sceneConfig.camera.aperture,
        sceneConfig.camera.focusDist,
        0
    };
    calculateBasisFromEuler(cameraRot[0], cameraRot[1], cameraRot[2],
                            camera_params.forward, camera_params.right, camera_params.up);

    SkyParams sky_params = { sceneConfig.sky.colorTop, sceneConfig.sky.colorBottom };

    int targetRenderWidth = sceneConfig.render.width;
    int targetRenderHeight = sceneConfig.render.height;
    int samplesPerFrame = sceneConfig.render.samplesPerFrame;
    int maxSamples = sceneConfig.render.maxSamples;
    int maxBounces = sceneConfig.render.maxBounces;

    RayTexture accumTexture = createTexture(targetRenderWidth, targetRenderHeight, GL_RGBA32F);
    RayTexture outputTexture = createTexture(targetRenderWidth, targetRenderHeight, GL_RGBA32F);

    RayTexture accumBloom = createTexture(targetRenderWidth, targetRenderHeight, GL_RGBA32F);
    RayTexture outputBloom = createTexture(targetRenderWidth, targetRenderHeight, GL_RGBA32F);

    auto resetAccumulation = [&]() {
        float clearColor[4] = {0.0f, 0.0f, 0.0f, 0.0f};
        glClearTexImage(accumTexture.id, 0, GL_RGBA, GL_FLOAT, clearColor);
        glClearTexImage(accumBloom.id, 0, GL_RGBA, GL_FLOAT, clearColor);
        camera_params.frameCount = 0;
    };

    QuadRenderer quadRenderer;
    GLuint uiFBO = 0;
    GLuint uiTexture = 0;
    UIResolution currentUIRes = {0, 0};

    GLuint timeQuery;
    glGenQueries(1, &timeQuery);
    GLuint64 elapsedNanoseconds = 0;

    bool isRendering = true;
    bool accumulationPaused = false;

    double uiUpdateInterval = 1.0 / static_cast<double>(monitorRefreshRate);
    double lastUITime = 0.0;

    BloomPipeline bloomPipeline;
    initBloomPipeline(bloomPipeline);
    GLuint bloomFBO = 0;

    while (!glfwWindowShouldClose(window)) {
        double currentTime = glfwGetTime();
        int winWidth, winHeight;
        glfwGetFramebufferSize(window, &winWidth, &winHeight);

        if (winWidth != currentUIRes.width || winHeight != currentUIRes.height) {
            currentUIRes.width = winWidth;
            currentUIRes.height = winHeight;
            createUIFramebuffer(winWidth, winHeight, &uiFBO, &uiTexture);
        }

        int currentTotalSamples = camera_params.frameCount * samplesPerFrame;
        bool isRenderingComplete = currentTotalSamples >= maxSamples;

        if (isRendering && !accumulationPaused && !isRenderingComplete) {
            sceneBuffer.bind(1);
            materialBuffer.bind(2);
            glBeginQuery(GL_TIME_ELAPSED, timeQuery);

            dispatchComputeShader(computeProgram,
                                  accumTexture.id, outputTexture.id,
                                  accumBloom.id, outputBloom.id,
                                  {accumTexture.width, accumTexture.height},
                                  camera_params, sky_params,
                                  sceneData.objects.size(),
                                  static_cast<int>(sceneData.lightIndices.size()),
                                  samplesPerFrame, maxSamples,
                                  static_cast<uint32_t>(maxBounces));

            glEndQuery(GL_TIME_ELAPSED);
            camera_params.frameCount += 1;
            glGetQueryObjectui64v(timeQuery, GL_QUERY_RESULT, &elapsedNanoseconds);
        }

        BloomFrameResult bloomResult{};
        if (sceneConfig.render.bloom.enabled) {
            bloomResult = applyBloom(sceneConfig.render.bloom, bloomPipeline, bloomFBO,
                                     outputBloom.id,
                                     outputBloom.width, outputBloom.height,
                                     quadRenderer);
        }
        const bool bloomActive = sceneConfig.render.bloom.enabled && bloomResult.textureId != 0;

        // Render to Screen
        glBindFramebuffer(GL_FRAMEBUFFER, 0);
        glViewport(0, 0, winWidth, winHeight);
        glDisable(GL_BLEND);
        glUseProgram(renderProgram);

        const GLint bloomEnabledLoc = glGetUniformLocation(renderProgram, "bloomEnabled");
        const GLint bloomTextureLoc = glGetUniformLocation(renderProgram, "bloomTexture");
        const GLint bloomIntensityLoc = glGetUniformLocation(renderProgram, "bloomIntensity");

        glUniform2f(glGetUniformLocation(renderProgram, "renderResolution"),
                    static_cast<float>(outputTexture.width), static_cast<float>(outputTexture.height));
        glUniform2f(glGetUniformLocation(renderProgram, "windowResolution"),
                    static_cast<float>(winWidth), static_cast<float>(winHeight));

        glUniform1i(bloomTextureLoc, 1);
        glUniform1i(bloomEnabledLoc, bloomActive ? 1 : 0);
        glUniform1f(bloomIntensityLoc, sceneConfig.render.bloom.intensity);

        glActiveTexture(GL_TEXTURE1);
        glBindTexture(GL_TEXTURE_2D, bloomActive ? bloomResult.textureId : 0);

        glActiveTexture(GL_TEXTURE0);
        glBindTexture(GL_TEXTURE_2D, outputTexture.id);
        glUniform1i(glGetUniformLocation(renderProgram, "rayTexture"), 0);

        quadRenderer.render();

        // UI
        if (currentTime - lastUITime >= uiUpdateInterval) {
            lastUITime = currentTime;

            glBindFramebuffer(GL_FRAMEBUFFER, uiFBO);
            glViewport(0, 0, winWidth, winHeight);
            glClearColor(0, 0, 0, 0);
            glClear(GL_COLOR_BUFFER_BIT);

            ImGui_ImplOpenGL3_NewFrame();
            ImGui_ImplGlfw_NewFrame();
            ImGui::NewFrame();

            ImGui::Begin("Raypulse Controls");
            float gpuTimeMs = elapsedNanoseconds / 1000000.0f;
            ImGui::TextColored(ImVec4(0, 1, 0, 1), "Raytrace Speed: %.0f FPS", 1000.0f / (gpuTimeMs + 0.0001f));
            ImGui::Text("Render Res: %dx%d", accumTexture.width, accumTexture.height);

            if (isRenderingComplete) {
                ImGui::PushStyleColor(ImGuiCol_Text, ImVec4(0.0f, 1.0f, 0.0f, 1.0f));
                ImGui::Text("RENDERING COMPLETE (%d Samples)", maxSamples);
                ImGui::PopStyleColor();
                ImGui::ProgressBar(1.0f, ImVec2(-1.0f, 0.0f), "Done");
            }
            else if (accumulationPaused) {
                ImGui::PushStyleColor(ImGuiCol_Text, ImVec4(1.0f, 1.0f, 0.0f, 1.0f));
                ImGui::Text("PAUSED (%d / %d)", currentTotalSamples, maxSamples);
                ImGui::PopStyleColor();
                float progress = (float)currentTotalSamples / (float)maxSamples;
                ImGui::ProgressBar(progress, ImVec2(-1.0f, 0.0f), "Paused");
            }
            else {
                float progress = (float)currentTotalSamples / (float)maxSamples;
                char overlay[32];
                sprintf(overlay, "%d / %d Samples", currentTotalSamples, maxSamples);
                ImGui::ProgressBar(progress, ImVec2(-1.0f, 0.0f), overlay);
            }
            ImGui::Separator();
            if (ImGui::CollapsingHeader("Resolution Settings", ImGuiTreeNodeFlags_DefaultOpen)) {
                ImGui::InputInt("Width", &targetRenderWidth);
                ImGui::InputInt("Height", &targetRenderHeight);

                if (ImGui::Button("Set Resolution")) {
                    if (targetRenderWidth > 0 && targetRenderHeight > 0) {
                        resizeTexture(accumTexture, targetRenderWidth, targetRenderHeight, GL_RGBA32F);
                        resizeTexture(outputTexture, targetRenderWidth, targetRenderHeight, GL_RGBA32F);
                        resizeTexture(accumBloom, targetRenderWidth, targetRenderHeight, GL_RGBA32F);
                        resizeTexture(outputBloom, targetRenderWidth, targetRenderHeight, GL_RGBA32F);

                        resetAccumulation();
                        createUIFramebuffer(winWidth, winHeight, &uiFBO, &uiTexture);
                    }
                }

                if (ImGui::CollapsingHeader("Progressive Rendering", ImGuiTreeNodeFlags_DefaultOpen)) {
                    ImGui::SliderInt("Max Samples", &maxSamples, 10, 100000);
                    ImGui::SliderInt("Samples / Frame", &samplesPerFrame, 1, 16);

                    if (ImGui::SliderInt("Max Bounces", &maxBounces, 1, 256)) {
                        resetAccumulation();
                    }

                    ImGui::Separator();
                    if (ImGui::Button("Restart")) {
                        resetAccumulation();
                    }
                    ImGui::SameLine();
                    if (ImGui::Button(accumulationPaused ? "Resume" : "Pause")) {
                        accumulationPaused = !accumulationPaused;
                    }
                }

                if (ImGui::CollapsingHeader("Bloom", ImGuiTreeNodeFlags_DefaultOpen)) {
                    ImGui::Checkbox("Enable Bloom", &sceneConfig.render.bloom.enabled);
                    ImGui::SliderFloat("Threshold", &sceneConfig.render.bloom.threshold, 0.0f, 20.0f, "%.2f");
                    ImGui::SliderFloat("Soft Knee", &sceneConfig.render.bloom.knee, 0.0f, 1.0f, "%.2f");
                    ImGui::SliderFloat("Intensity", &sceneConfig.render.bloom.intensity, 0.0f, 5.0f, "%.2f");
                    ImGui::SliderInt("Blur Iterations", &sceneConfig.render.bloom.iterations, 1, 8);
                    ImGui::SliderFloat("Downscale", &sceneConfig.render.bloom.downscale, 0.1f, 1.0f, "%.2f");
                    sceneConfig.render.bloom.knee = std::clamp(sceneConfig.render.bloom.knee, 0.0f, 1.0f);
                    sceneConfig.render.bloom.downscale = std::clamp(sceneConfig.render.bloom.downscale, 0.1f, 1.0f);
                    sceneConfig.render.bloom.iterations = std::clamp(sceneConfig.render.bloom.iterations, 1, 8);
                }
            }

            ImGui::Separator();
            if (ImGui::CollapsingHeader("Camera", ImGuiTreeNodeFlags_DefaultOpen)) {
                ImGui::DragFloat3("Position", glm::value_ptr(camera_params.pos), 0.1f);
                const float prevRot[3] = {cameraRot[0], cameraRot[1], cameraRot[2]};
                ImGui::SliderFloat("Pitch (X)", &cameraRot[0], -90.0f, 90.0f, "%.1f°");
                ImGui::SliderFloat("Yaw (Y)", &cameraRot[1], -180.0f, 180.0f, "%.1f°");
                ImGui::SliderFloat("Roll (Z)", &cameraRot[2], -180.0f, 180.0f, "%.1f°");
                ImGui::SliderFloat("FOV", &camera_params.FOV, 20.0f, 150.0f, "%.1f°");

                ImGui::Separator();
                ImGui::Text("Depth of Field");
                ImGui::SliderFloat("Aperture", &sceneConfig.camera.aperture, 0.0f, 2.0f, "%.3f");
                ImGui::DragFloat("Focus Dist", &sceneConfig.camera.focusDist, 0.1f, 0.1f, 100.0f, "%.2f");

                static glm::vec3 prevCameraPos = camera_params.pos;
                static glm::vec3 prevCameraRot = cameraRot;
                static float prevFOV = camera_params.FOV;
                static float prevAperture = sceneConfig.camera.aperture;
                static float prevFocusDist = sceneConfig.camera.focusDist;

                bool cameraChanged = (prevCameraPos != camera_params.pos) ||
                    (prevCameraRot != cameraRot) || (prevFOV != camera_params.FOV) ||
                    (prevAperture != sceneConfig.camera.aperture) ||
                    (prevFocusDist != sceneConfig.camera.focusDist);

                if (cameraChanged) {
                    resetAccumulation();

                    prevCameraPos = camera_params.pos;
                    prevCameraRot = cameraRot;
                    prevFOV = camera_params.FOV;
                    prevAperture = sceneConfig.camera.aperture;
                    prevFocusDist = sceneConfig.camera.focusDist;
                }

                camera_params.aperture = sceneConfig.camera.aperture;
                camera_params.focusDist = sceneConfig.camera.focusDist;

                const bool rotationChanged = (prevRot[0] != cameraRot[0]) ||
                    (prevRot[1] != cameraRot[1]) || (prevRot[2] != cameraRot[2]);

                if (rotationChanged) {
                    calculateBasisFromEuler(cameraRot[0], cameraRot[1], cameraRot[2],
                                            camera_params.forward, camera_params.right, camera_params.up);
                }
            }

            if (ImGui::CollapsingHeader("Sky Colors", ImGuiTreeNodeFlags_DefaultOpen)) {
                if(ImGui::ColorEdit3("Bottom Color", glm::value_ptr(sky_params.colorBottom)) ||
                   ImGui::ColorEdit3("Top Color", glm::value_ptr(sky_params.colorTop))) {
                    resetAccumulation();
                }
            }

            ImGui::Separator();
            if (ImGui::Button("Save .exr")) {
                const char* filename = generateTimestampedFilename("raypulse", ".exr");
                saveToEXR(outputTexture.id, outputTexture.width, outputTexture.height, filename);
            }
            ImGui::End();

            ImGui::Render();
            ImGui_ImplOpenGL3_RenderDrawData(ImGui::GetDrawData());
        }

        glBindFramebuffer(GL_FRAMEBUFFER, 0);
        glViewport(0, 0, winWidth, winHeight);
        glEnable(GL_BLEND);
        glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
        glUseProgram(renderProgram);
        glUniform1i(bloomEnabledLoc, 0);
        glUniform2f(glGetUniformLocation(renderProgram, "renderResolution"), (float)winWidth, (float)winHeight);
        glUniform2f(glGetUniformLocation(renderProgram, "windowResolution"), (float)winWidth, (float)winHeight);
        glActiveTexture(GL_TEXTURE0);
        glBindTexture(GL_TEXTURE_2D, uiTexture);
        glUniform1i(glGetUniformLocation(renderProgram, "rayTexture"), 0);
        quadRenderer.render();

        processInput(window);
        glfwSwapBuffers(window);
        glfwPollEvents();
    }

    glDeleteFramebuffers(1, &uiFBO);
    if (bloomFBO) glDeleteFramebuffers(1, &bloomFBO);
    glDeleteTextures(1, &uiTexture);
    ImGui_ImplOpenGL3_Shutdown();
    ImGui_ImplGlfw_Shutdown();
    ImGui::DestroyContext();
    destroyBloomPipeline(bloomPipeline);
    destroyTexture(accumTexture);
    destroyTexture(outputTexture);
    destroyTexture(accumBloom);
    destroyTexture(outputBloom);
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

void createUIFramebuffer(const int width, const int height, GLuint* fbo, GLuint* tex) {
    if (*fbo) glDeleteFramebuffers(1, fbo);
    if (*tex) glDeleteTextures(1, tex);
    glGenFramebuffers(1, fbo);
    glBindFramebuffer(GL_FRAMEBUFFER, *fbo);
    glGenTextures(1, tex);
    glBindTexture(GL_TEXTURE_2D, *tex);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, width, height, 0, GL_RGBA, GL_UNSIGNED_BYTE, nullptr);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, *tex, 0);
    if (glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE) printf("Error: UI Framebuffer is not complete!\n");
    glBindFramebuffer(GL_FRAMEBUFFER, 0);
}