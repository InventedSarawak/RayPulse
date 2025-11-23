#pragma once
#include <optional>
#include <string>
#include <vector>
#include <glm/glm.hpp>

// Scene metadata
struct SceneInfo {
    std::string name = "Untitled Scene";
    std::string version = "1.0";
};

// Camera configuration
struct CameraConfig {
    glm::vec3 position = glm::vec3(0.1f, 0.5f, 0.0f);
    glm::vec3 rotation = glm::vec3(0.0f, 0.0f, 0.0f); // pitch, yaw, roll
    float fov = 60.0f;
};

// Sky/environment configuration
struct SkyConfig {
    glm::vec3 colorTop = glm::vec3(0.5f, 0.7f, 1.0f);
    glm::vec3 colorBottom = glm::vec3(0.98f, 0.98f, 0.98f);
};

// Render settings
struct RenderConfig {
    int width = 1600;
    int height = 900;
    int samplesPerFrame = 8;
    int maxSamples = 5000;
    int maxBounces = 8;
};

// Material definition from file
struct MaterialConfig {
    std::string name;
    std::string template_type; // Optional: "lambertian", "metal", etc.
    
    // All properties optional (will use template/default if not specified)
    std::optional<glm::vec3> albedo;
    std::optional<glm::vec3> emission;
    std::optional<float> emissionStrength;

    std::optional<float> roughness;
    std::optional<float> metallic;
    std::optional<float> transmission;
    std::optional<float> ior;

    std::optional<glm::vec3> specularTint;
    std::optional<float> specular;

    std::optional<float> clearcoat;
    std::optional<float> clearcoatRoughness;
    std::optional<float> subsurface;

    std::optional<glm::vec3> absorption;
    std::optional<float> sheen;

    std::optional<float> subsurfaceRadius;
    std::optional<float> scatteringAnisotropy;
};

// Object definition from file
struct ObjectConfig {
    std::string type; // "sphere" or "plane"
    std::string material; // Material name reference
    bool isLight = false; // Mark for NEE (future use)
    
    // Sphere properties
    glm::vec3 center = glm::vec3(0.0f);
    float radius = 1.0f;
    
    // Plane properties
    glm::vec3 normal = glm::vec3(0.0f, 1.0f, 0.0f);
    float distance = 0.0f;
};

// Top-level scene structure
struct SceneConfig {
    SceneInfo scene;
    CameraConfig camera;
    SkyConfig sky;
    RenderConfig render;
    std::vector<MaterialConfig> materials;
    std::vector<ObjectConfig> objects;
};