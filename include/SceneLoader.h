#pragma once
#include <string>
#include <optional>
#include "SceneConfig.h"

class SceneLoader {
public:
    // Load scene from file
    static std::optional<SceneConfig> loadFromFile(const std::string& filepath);
    
    // Load from JSON string (for testing)
    static std::optional<SceneConfig> loadFromString(const std::string& jsonString);
    
    // Get last error message
    static std::string getLastError();
    
private:
    static std::string lastError;
};