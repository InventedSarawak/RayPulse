#include "MaterialFactory.h"

GPUMaterial MaterialFactory::applyTemplate(const std::string& templateType) {
    // [Template logic remains the same, simplified here for brevity]
    if (templateType == "lambertian") return MaterialBuilder::Lambertian(glm::vec3(0.5f));
    if (templateType == "metal") return MaterialBuilder::Metal(glm::vec3(0.5f), 0.0f);
    if (templateType == "dielectric") return MaterialBuilder::Dielectric(1.5f);
    if (templateType == "emissive") return MaterialBuilder::Emissive(glm::vec3(1.0f), 1.0f);
    if (templateType == "plastic") return MaterialBuilder::Plastic(glm::vec3(0.5f), 0.5f);
    if (templateType == "velvet") return MaterialBuilder::Velvet(glm::vec3(0.5f), 1.0f);
    if (templateType == "satin") return MaterialBuilder::Satin(glm::vec3(0.5f));
    if (templateType == "clearcoat") return MaterialBuilder::Clearcoat(glm::vec3(0.5f));
    if (templateType == "glass") return MaterialBuilder::ColoredGlass(glm::vec3(1.0f), 1.5f, 2.0f);
    return MaterialBuilder::Default();
}

GPUMaterial MaterialFactory::buildMaterial(const MaterialConfig& config) {
    // 1. Start with the template (sets defaults like Transmission=1.0 for glass)
    GPUMaterial mat = applyTemplate(config.template_type);

    // 2. Only override if the user explicitly provided a value in JSON

    if (config.albedo.has_value()) mat.albedo = config.albedo.value();
    if (config.emission.has_value()) mat.emission = config.emission.value();
    if (config.emissionStrength.has_value()) mat.emissionStrength = config.emissionStrength.value();

    if (config.roughness.has_value()) mat.roughness = config.roughness.value();
    if (config.metallic.has_value()) mat.metallic = config.metallic.value();
    if (config.transmission.has_value()) mat.transmission = config.transmission.value();
    if (config.ior.has_value()) mat.ior = config.ior.value();

    if (config.specularTint.has_value()) mat.specularTint = config.specularTint.value();
    if (config.specular.has_value()) mat.specular = config.specular.value();

    if (config.clearcoat.has_value()) mat.clearcoat = config.clearcoat.value();
    if (config.clearcoatRoughness.has_value()) mat.clearcoatRoughness = config.clearcoatRoughness.value();
    if (config.subsurface.has_value()) mat.subsurface = config.subsurface.value();

    if (config.absorption.has_value()) mat.absorption = config.absorption.value();
    if (config.sheen.has_value()) mat.sheen = config.sheen.value();

    if (config.subsurfaceRadius.has_value()) mat.subsurfaceRadius = config.subsurfaceRadius.value();
    if (config.scatteringAnisotropy.has_value()) mat.scatteringAnisotropy = config.scatteringAnisotropy.value();
    
    return mat;
}