#pragma once
#include <vector>
#include <map>
#include <string>
#include "SceneConfig.h"
#include "renderer.h"
#include "material.h"

struct SceneData {
    std::vector<GPUObject> objects;
    std::vector<GPUMaterial> materials;
    std::vector<int> lightIndices;
    
    // Material name → GPU buffer index mapping
    std::map<std::string, int> materialMap;
};

class SceneBuilder {
public:
    // Convert SceneConfig → GPU-ready data
    static SceneData buildScene(const SceneConfig& config);
    
    // Validate scene (check for missing materials, etc.)
    static bool validate(const SceneConfig& config, std::string& errorMsg);
    
private:
    static std::map<std::string, int> buildMaterialMap(
        const std::vector<MaterialConfig>& materialConfigs,
        std::vector<GPUMaterial>& gpuMaterials
    );

    static int resolveMaterialIndex(
        const std::string& materialName,
        const std::map<std::string, int>& materialMap
    );
};