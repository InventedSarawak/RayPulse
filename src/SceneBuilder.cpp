#include "SceneBuilder.h"
#include "MaterialFactory.h"
#include <iostream>
#include <set>

bool SceneBuilder::validate(const SceneConfig& config, std::string& errorMsg) {
    if (config.materials.empty()) {
        errorMsg = "Scene has no materials defined";
        return false;
    }

    if (config.objects.empty()) {
        errorMsg = "Scene has no objects defined";
        return false;
    }
    
    // Build material name set for validation
    std::set<std::string> materialNames;
    for (const auto& mat : config.materials) {
        if (mat.name.empty()) {
            errorMsg = "Material with empty name found";
            return false;
        }
        
        if (materialNames.count(mat.name) > 0) {
            errorMsg = "Duplicate material name: " + mat.name;
            return false;
        }
        
        materialNames.insert(mat.name);
    }
    
    // Validate object material references
    for (size_t i = 0; i < config.objects.size(); i++) {
        const auto& obj = config.objects[i];
        
        if (obj.material.empty()) {
            errorMsg = "Object " + std::to_string(i) + " has no material assigned";
            return false;
        }
        
        if (materialNames.count(obj.material) == 0) {
            errorMsg = "Object " + std::to_string(i) + " references unknown material: " + obj.material;
            return false;
        }
        
        // Validate geometry
        if (obj.type == "sphere" && obj.radius <= 0.0f) {
            errorMsg = "Object " + std::to_string(i) + " (sphere) has invalid radius: " + std::to_string(obj.radius);
            return false;
        }
        
        if (obj.type == "plane") {
            float normalLen = glm::length(obj.normal);
            if (normalLen < 0.001f) {
                errorMsg = "Object " + std::to_string(i) + " (plane) has invalid normal (near zero)";
                return false;
            }
        }
    }
    
    return true;
}

std::map<std::string, int> SceneBuilder::buildMaterialMap(
    const std::vector<MaterialConfig>& materialConfigs,
    std::vector<GPUMaterial>& gpuMaterials
) {
    std::map<std::string, int> materialMap;
    
    for (const auto& matConfig : materialConfigs) {
        const int index = static_cast<int>(gpuMaterials.size());
        
        // Build GPU material from config
        GPUMaterial gpuMat = MaterialFactory::buildMaterial(matConfig);
        gpuMaterials.push_back(gpuMat);
        
        // Map name → index
        materialMap[matConfig.name] = index;
        
        std::cout << "  Material '" << matConfig.name << "' → index " << index << std::endl;
    }
    
    return materialMap;
}

int SceneBuilder::resolveMaterialIndex(
    const std::string& materialName,
    const std::map<std::string, int>& materialMap
) {
    auto it = materialMap.find(materialName);
    if (it != materialMap.end()) {
        return it->second;
    }

    std::cerr << "Warning: Material '" << materialName << "' not found, using index 0" << std::endl;
    return 0;
}

SceneData SceneBuilder::buildScene(const SceneConfig& config) {
    SceneData sceneData;
    
    std::cout << "Building scene: " << config.scene.name << std::endl;

    std::cout << "Building materials..." << std::endl;
    sceneData.materialMap = buildMaterialMap(config.materials, sceneData.materials);

    std::cout << "Building objects..." << std::endl;
    for (size_t i = 0; i < config.objects.size(); i++) {
        const auto& objConfig = config.objects[i];

        int matIndex = resolveMaterialIndex(objConfig.material, sceneData.materialMap);

        GPUObject gpuObj;
        
        if (objConfig.type == "sphere") {
            gpuObj = makeSphere(objConfig.center, objConfig.radius, matIndex);
            std::cout << "  Sphere at (" << objConfig.center.x << ", " << objConfig.center.y 
                      << ", " << objConfig.center.z << "), radius=" << objConfig.radius 
                      << ", material='" << objConfig.material << "'" << std::endl;
        }
        else if (objConfig.type == "plane") {
            gpuObj = makePlane(objConfig.normal, objConfig.distance, matIndex);
            std::cout << "  Plane normal=(" << objConfig.normal.x << ", " << objConfig.normal.y 
                      << ", " << objConfig.normal.z << "), distance=" << objConfig.distance 
                      << ", material='" << objConfig.material << "'" << std::endl;
        }
        else {
            std::cerr << "  Warning: Unknown object type '" << objConfig.type << "', skipping" << std::endl;
            continue;
        }
        
        sceneData.objects.push_back(gpuObj);
        
        // Track lights for NEE
        if (objConfig.isLight) {
            sceneData.lightIndices.push_back(static_cast<int>(sceneData.objects.size() - 1));
            std::cout << "    → Marked as light source" << std::endl;
        }
    }
    
    std::cout << "Scene built: " << sceneData.objects.size() << " objects, " 
              << sceneData.materials.size() << " materials, "
              << sceneData.lightIndices.size() << " lights" << std::endl;
    
    return sceneData;
}