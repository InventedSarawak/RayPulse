#pragma once
#include <glm/glm.hpp>

enum EmissionMode {
    EMISSION_PHYSICAL = 0,    // Standard additive lighting
    EMISSION_ABSOLUTE = 1     // Multiplicative tinting/filtering
};

struct GPUMaterial {
    glm::vec3 albedo;           // Base color
    float _pad0;

    glm::vec3 emission;         // Emitted light color / tint color
    float emissionStrength;     // Intensity multiplier

    float roughness;            // 0 = mirror, 1 = matte
    float metallic;             // 0 = dielectric, 1 = metal
    float transmission;         // 0 = opaque, 1 = transparent
    float ior;

    glm::vec3 specularTint;     // F0 color override
    float specular;             // Specular strength multiplier

    float clearcoat;            // Secondary glossy layer strength
    float clearcoatRoughness;   // Coating roughness
    float subsurface;           // Translucency amount
    int emissionMode;           // EMISSION_PHYSICAL or EMISSION_ABSOLUTE

    glm::vec3 absorption;       // Beer's Law absorption coefficients
    float sheen;                // Fabric-like edge glow
};

class MaterialBuilder {
public:
    static GPUMaterial Default() {
        GPUMaterial m{};
        m.albedo = glm::vec3(0.5f);
        m.emission = glm::vec3(0.0f);
        m.emissionStrength = 0.0f;
        m.roughness = 0.5f;
        m.metallic = 0.0f;
        m.transmission = 0.0f;
        m.ior = 1.45f;
        m.specularTint = glm::vec3(1.0f);
        m.specular = 0.5f;
        m.clearcoat = 0.0f;
        m.clearcoatRoughness = 0.03f;
        m.subsurface = 0.0f;
        m.emissionMode = EMISSION_PHYSICAL;
        m.absorption = glm::vec3(0.0f);
        m.sheen = 0.0f;
        return m;
    }

    static GPUMaterial Lambertian(const glm::vec3& albedo) {
        auto m = Default();
        m.albedo = albedo;
        m.roughness = 1.0f;
        m.metallic = 0.0f;
        m.transmission = 0.0f;
        return m;
    }

    static GPUMaterial Metal(const glm::vec3& albedo, float roughness = 0.0f) {
        auto m = Default();
        m.albedo = albedo;
        m.roughness = roughness;
        m.metallic = 1.0f;
        m.transmission = 0.0f;
        return m;
    }

    static GPUMaterial Dielectric(float ior = 1.5f) {
        auto m = Default();
        m.albedo = glm::vec3(1.0f);
        m.roughness = 0.0f;
        m.metallic = 0.0f;
        m.transmission = 1.0f;
        m.ior = ior;
        return m;
    }

    static GPUMaterial Emissive(const glm::vec3& color, float strength = 1.0f) {
        auto m = Default();
        m.emission = color;
        m.emissionStrength = strength;
        m.emissionMode = EMISSION_PHYSICAL;
        m.albedo = glm::vec3(0.0f);
        m.roughness = 1.0f;
        return m;
    }

    static GPUMaterial Plastic(const glm::vec3& albedo, float roughness = 0.5f) {
        auto m = Default();
        m.albedo = albedo;
        m.roughness = roughness;
        m.metallic = 0.0f;
        m.ior = 1.45f;
        m.specular = 0.5f;
        return m;
    }

    static GPUMaterial Clearcoat(const glm::vec3& albedo, float clearcoatAmount = 0.5f) {
        auto m = Default();
        m.albedo = albedo;
        m.roughness = 0.6f;
        m.metallic = 0.0f;
        m.clearcoat = clearcoatAmount;
        m.clearcoatRoughness = 0.03f;
        m.ior = 1.5f;
        return m;
    }

    // NEW: Color filter/tint effect
    static GPUMaterial ColorFilter(const glm::vec3& tintColor, float strength = 0.5f) {
        auto m = Default();
        m.emission = tintColor;
        m.emissionStrength = strength;
        m.emissionMode = EMISSION_ABSOLUTE;
        m.albedo = glm::vec3(0.0f);
        return m;
    }

    // NEW: Dark void
    static GPUMaterial DarkVoid(float strength = 0.9f) {
        auto m = Default();
        m.emission = glm::vec3(0.0f);
        m.emissionStrength = strength;
        m.emissionMode = EMISSION_ABSOLUTE;
        m.albedo = glm::vec3(0.0f);
        return m;
    }
};