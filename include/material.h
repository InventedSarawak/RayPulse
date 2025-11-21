#pragma once
#include <glm/glm.hpp>

enum MaterialType {
    MAT_LAMBERTIAN = 0,
    MAT_METAL = 1,
    MAT_DIELECTRIC = 2,
    MAT_EMISSIVE = 3,
    MAT_PLASTIC = 4,
    MAT_CLEARCOAT = 5
};

struct TextureIndices {
    int albedo = -1;
    int normal = -1;
    int roughness = -1;
    int metallic = -1;
    int emission = -1;
};

// Matches GPU layout exactly (std430)
struct GPUMaterial {
    // Color properties (16 bytes)
    glm::vec3 albedo;
    float _pad0;
    
    // Physical properties (16 bytes)
    glm::vec3 emission;
    float ior;
    
    // Surface properties (16 bytes)
    float roughness;
    float metallic;
    float specular;
    float transmission;
    
    // Material behavior (16 bytes)
    int type;
    float subsurface;
    float clearcoat;
    float sheen;
};

// Helper builders (modern C++ factory pattern)
class MaterialBuilder {
public:
    static GPUMaterial Lambertian(const glm::vec3& albedo) {
        GPUMaterial m{};
        m.type = MAT_LAMBERTIAN;
        m.albedo = albedo;
        m.roughness = 1.0f;
        m.metallic = 0.0f;
        m.ior = 1.45f; // Default glass-ish
        return m;
    }
    
    static GPUMaterial Metal(const glm::vec3& albedo, float roughness = 0.0f) {
        GPUMaterial m{};
        m.type = MAT_METAL;
        m.albedo = albedo;
        m.roughness = roughness;
        m.metallic = 1.0f;
        m.ior = 1.0f; // Metals use complex IOR, simplified here
        return m;
    }
    
    static GPUMaterial Dielectric(float ior = 1.5f) {
        GPUMaterial m{};
        m.type = MAT_DIELECTRIC;
        m.albedo = glm::vec3(1.0f); // Clear glass
        m.roughness = 0.0f;
        m.metallic = 0.0f;
        m.ior = ior;
        m.transmission = 1.0f;
        return m;
    }
    
    static GPUMaterial Emissive(const glm::vec3& color, float strength = 1.0f) {
        GPUMaterial m{};
        m.type = MAT_EMISSIVE;
        m.emission = color * strength;
        m.albedo = glm::vec3(0.0f);
        return m;
    }
    
    static GPUMaterial Plastic(const glm::vec3& albedo, float roughness = 0.5f) {
        GPUMaterial m{};
        m.type = MAT_PLASTIC;
        m.albedo = albedo;
        m.roughness = roughness;
        m.metallic = 0.0f;
        m.ior = 1.45f;
        m.specular = 0.5f;
        return m;
    }
    
    // Layered material: glossy coating over diffuse base
    static GPUMaterial Clearcoat(const glm::vec3& albedo, float clearcoatAmount = 0.5f) {
        GPUMaterial m{};
        m.type = MAT_CLEARCOAT;
        m.albedo = albedo;
        m.roughness = 0.6f;
        m.metallic = 0.0f;
        m.clearcoat = clearcoatAmount;
        m.ior = 1.5f;
        return m;
    }
};