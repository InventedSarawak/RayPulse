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
        GPUMaterial gpuMat = MaterialFactory::buildMaterial(matConfig);
        gpuMaterials.push_back(gpuMat);
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
    return 0;
}

SceneData SceneBuilder::buildScene(const SceneConfig& config) {
    SceneData sceneData;

    std::cout << "Building scene: " << config.scene.name << std::endl;
    sceneData.materialMap = buildMaterialMap(config.materials, sceneData.materials);

    std::cout << "Building objects..." << std::endl;
    for (size_t i = 0; i < config.objects.size(); i++) {
        const auto& objConfig = config.objects[i];
        int matIndex = resolveMaterialIndex(objConfig.material, sceneData.materialMap);

        GPUObject gpuObj;
        glm::vec3 scale = glm::vec3(1.0f);
        int type = 0; // OBJ_SPHERE

        if (objConfig.type == "sphere") {
            type = 0; // OBJ_SPHERE
            scale = glm::vec3(objConfig.radius);
        }
        else if (objConfig.type == "plane") {
            type = 1; // OBJ_PLANE
            // Special packing for plane
            gpuObj.data1 = glm::vec4(objConfig.normal, objConfig.distance);
            gpuObj.data2 = glm::vec4(0.0f, 0.0f, 0.0f, (float)matIndex);
            gpuObj.data3 = glm::vec4(0.0f, 0.0f, 0.0f, (float)type);
            sceneData.objects.push_back(gpuObj);
            continue;
        }
        else if (objConfig.type == "cube" || objConfig.type == "box") {
            type = 2; // OBJ_CUBE
            // Scale for box is Half-Extents (Size / 2.0)
            scale = objConfig.size * 0.5f;
        }
        else if (objConfig.type == "cylinder") {
            type = 3; // OBJ_CYLINDER
            scale = glm::vec3(objConfig.radius, objConfig.height, objConfig.radius);
        }
        else if (objConfig.type == "cone") {
            type = 4; // OBJ_CONE
            scale = glm::vec3(objConfig.radius, objConfig.height, objConfig.radius);
        }
        else if (objConfig.type == "pyramid") {
            type = 5; // OBJ_PYRAMID
            scale = glm::vec3(objConfig.radius);
        }
        else if (objConfig.type == "tetrahedron") {
            type = 6; // OBJ_TETRAHEDRON
            scale = glm::vec3(objConfig.radius);
        }
        else if (objConfig.type == "prism") {
            type = 7; // OBJ_PRISM
            scale = glm::vec3(objConfig.radius, objConfig.height, objConfig.radius);
        }
        else if (objConfig.type == "dodecahedron") {
            type = 8; // OBJ_DODECAHEDRON
            scale = glm::vec3(objConfig.radius);
        }
        else if (objConfig.type == "icosahedron") {
            type = 9; // OBJ_ICOSAHEDRON
            scale = glm::vec3(objConfig.radius);
        }

        // Use the inline makeObject from renderer.h
        gpuObj = makeObject(type, objConfig.center, objConfig.rotation, scale, matIndex);
        sceneData.objects.push_back(gpuObj);

        if (objConfig.isLight) {
            sceneData.lightIndices.push_back((int)sceneData.objects.size() - 1);
        }
    }

    std::cout << "Scene built: " << sceneData.objects.size() << " objects, "
              << sceneData.materials.size() << " materials, "
              << sceneData.lightIndices.size() << " lights" << std::endl;

    return sceneData;
}