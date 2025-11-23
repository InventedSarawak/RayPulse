#pragma once
#include "material.h"
#include "SceneConfig.h"

class MaterialFactory {
public:
    // Build GPUMaterial from config (with template support)
    static GPUMaterial buildMaterial(const MaterialConfig& config);
    
private:
    // Apply template to base material
    static GPUMaterial applyTemplate(const std::string& templateType);
};