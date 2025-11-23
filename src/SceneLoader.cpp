#include "SceneLoader.h"
#include <json.hpp>
#include <fstream>
#include <iostream>

using json = nlohmann::json;

std::string SceneLoader::lastError;

static glm::vec3 parseVec3(const json& j, const glm::vec3& defaultValue = glm::vec3(0.0f)) {
    if (j.is_array() && j.size() >= 3) {
        return glm::vec3(j[0].get<float>(), j[1].get<float>(), j[2].get<float>());
    }
    return defaultValue;
}

static MaterialConfig parseMaterial(const json& j) {
    MaterialConfig mat;

    mat.name = j.value("name", "unnamed");
    mat.template_type = j.value("template", "");

    // Only set the optional if the key exists in JSON
    if (j.contains("albedo")) mat.albedo = parseVec3(j["albedo"]);
    if (j.contains("emission")) mat.emission = parseVec3(j["emission"]);
    if (j.contains("emissionStrength")) mat.emissionStrength = j["emissionStrength"].get<float>();

    if (j.contains("roughness")) mat.roughness = j["roughness"].get<float>();
    if (j.contains("metallic")) mat.metallic = j["metallic"].get<float>();
    if (j.contains("transmission")) mat.transmission = j["transmission"].get<float>();
    if (j.contains("ior")) mat.ior = j["ior"].get<float>();

    if (j.contains("specularTint")) mat.specularTint = parseVec3(j["specularTint"]);
    if (j.contains("specular")) mat.specular = j["specular"].get<float>();

    if (j.contains("clearcoat")) mat.clearcoat = j["clearcoat"].get<float>();
    if (j.contains("clearcoatRoughness")) mat.clearcoatRoughness = j["clearcoatRoughness"].get<float>();
    if (j.contains("subsurface")) mat.subsurface = j["subsurface"].get<float>();

    if (j.contains("absorption")) mat.absorption = parseVec3(j["absorption"]);
    if (j.contains("sheen")) mat.sheen = j["sheen"].get<float>();

    if (j.contains("subsurfaceRadius")) mat.subsurfaceRadius = j["subsurfaceRadius"].get<float>();
    if (j.contains("scatteringAnisotropy")) mat.scatteringAnisotropy = j["scatteringAnisotropy"].get<float>();

    return mat;
}

static ObjectConfig parseObject(const json& j) {
    ObjectConfig obj;

    obj.type = j.value("type", "sphere");
    obj.material = j.value("material", "default");
    obj.isLight = j.value("isLight", false);

    if (obj.type == "sphere") {
        obj.center = parseVec3(j["center"], glm::vec3(0.0f));
        obj.radius = j.value("radius", 1.0f);
    } else if (obj.type == "plane") {
        obj.normal = parseVec3(j["normal"], glm::vec3(0.0f, 1.0f, 0.0f));
        obj.distance = j.value("distance", 0.0f);
    }

    return obj;
}

static std::string formatParseError(const json::exception& e, const std::string& filepath) {
    std::string msg = "JSON Parse Error in '" + filepath + "':\n";
    msg += "  " + std::string(e.what()) + "\n";
    return msg;
}

std::optional<SceneConfig> SceneLoader::loadFromString(const std::string& jsonString) {
    try {
        json j = json::parse(jsonString, nullptr, true, true);

        SceneConfig config;

        if (j.contains("scene")) {
            config.scene.name = j["scene"].value("name", config.scene.name);
            config.scene.version = j["scene"].value("version", config.scene.version);
        }

        if (j.contains("camera")) {
            const auto& cam = j["camera"];
            config.camera.position = parseVec3(cam["position"], config.camera.position);
            config.camera.rotation = parseVec3(cam["rotation"], config.camera.rotation);
            config.camera.fov = cam.value("fov", config.camera.fov);
        }

        if (j.contains("sky")) {
            const auto& sky = j["sky"];
            config.sky.colorTop = parseVec3(sky["colorTop"], config.sky.colorTop);
            config.sky.colorBottom = parseVec3(sky["colorBottom"], config.sky.colorBottom);
        }

        if (j.contains("render")) {
            const auto& render = j["render"];
            config.render.width = render.value("width", config.render.width);
            config.render.height = render.value("height", config.render.height);
            config.render.samplesPerFrame = render.value("samplesPerFrame", config.render.samplesPerFrame);
            config.render.maxSamples = render.value("maxSamples", config.render.maxSamples);
            config.render.maxBounces = render.value("maxBounces", config.render.maxBounces);
        }

        if (j.contains("materials")) {
            for (const auto& matJson : j["materials"]) {
                config.materials.push_back(parseMaterial(matJson));
            }
        }

        if (j.contains("objects")) {
            for (const auto& objJson : j["objects"]) {
                config.objects.push_back(parseObject(objJson));
            }
        }

        return config;

    } catch (const json::exception& e) {
        lastError = std::string("JSON parse error: ") + e.what();
        return std::nullopt;
    } catch (const std::exception& e) {
        lastError = std::string("Error: ") + e.what();
        return std::nullopt;
    }
}

std::optional<SceneConfig> SceneLoader::loadFromFile(const std::string& filepath) {
    try {
        std::ifstream file(filepath);
        if (!file.is_open()) {
            lastError = "Could not open file: " + filepath + "\n";
            lastError += "Make sure the file exists and is readable.";
            return std::nullopt;
        }

        std::string content((std::istreambuf_iterator<char>(file)),
                           std::istreambuf_iterator<char>());

        if (content.empty()) {
            lastError = "File is empty: " + filepath;
            return std::nullopt;
        }

        return loadFromString(content);

    } catch (const json::exception& e) {
        lastError = formatParseError(e, filepath);
        return std::nullopt;
    } catch (const std::exception& e) {
        lastError = "File error: " + std::string(e.what());
        return std::nullopt;
    }
}

std::string SceneLoader::getLastError() {
    return lastError;
}