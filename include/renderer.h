#pragma once
#include <vector>
#include <glad/gl.h>
#include <glm/glm.hpp>

#include "material.h"

struct QuadVertex {
    glm::vec2 position;
    glm::vec2 texCoord;
};

class QuadRenderer {
public:
    QuadRenderer();
    ~QuadRenderer();
    
    void render() const;
    GLuint getVAO() const { return VAO; }
    
private:
    GLuint VAO;
    GLuint VBO;
};

enum ObjectType {
    OBJ_SPHERE = 0,
    OBJ_PLANE = 1,
    OBJ_CUBE = 2,
    OBJ_CYLINDER = 3,
    OBJ_CONE = 4,
    OBJ_PYRAMID = 5,
    OBJ_TETRAHEDRON = 6,
    OBJ_PRISM = 7,
    OBJ_DODECAHEDRON = 8,
    OBJ_ICOSAHEDRON = 9
};

// The Generic GPU Object (64 bytes)
// Matches std430 layout: vec4 x 4
struct GPUObject {
    // Data 1: Bounding Info
    // xyz = Center Position
    // w   = Bounding Radius (for quick culling)
    glm::vec4 data1;

    // Data 2: Orientation & Material
    // xyz = Rotation (Euler angles in degrees)
    // w   = Material Index
    glm::vec4 data2;

    // Data 3: Dimensions & Type
    // xyz = Scale/Dimensions (usage depends on type)
    // w   = Object Type ID
    glm::vec4 data3;

    // Data 4: Padding/Extra
    glm::vec4 data4;
};

inline GPUObject makeObject(int type, glm::vec3 center, glm::vec3 rot, glm::vec3 scale, int matIdx) {
    GPUObject obj{};
    obj.data1 = glm::vec4(center, glm::length(scale)); // Approx bounding radius
    obj.data2 = glm::vec4(rot, static_cast<float>(matIdx));
    obj.data3 = glm::vec4(scale, static_cast<float>(type));
    return obj;
}

inline GPUObject makeSphere(const glm::vec3 center, const float radius, const int matIndex = 0) {
    GPUObject obj{};
    obj.data1 = glm::vec4(center, radius);
    obj.data2 = glm::vec4(static_cast<float>(matIndex), 0.0f, 0.0f, static_cast<float>(OBJ_SPHERE));
    return obj;
}

inline GPUObject makePlane(const glm::vec3 normal, float dist, int matIndex = 0) {
    GPUObject obj{};
    obj.data1 = glm::vec4(normal, dist);
    obj.data2 = glm::vec4(static_cast<float>(matIndex), 0.0f, 0.0f, static_cast<float>(OBJ_PLANE));
    return obj;
}

class SceneBuffer {
public:
    SceneBuffer();
    ~SceneBuffer();

    // Uploads the list of hittables to the GPU
    void update(const std::vector<GPUObject>& objects) const;
    void bind(GLuint bindingPoint) const;

private:
    GLuint ssbo{};
};

class MaterialBuffer {
public:
    MaterialBuffer();
    ~MaterialBuffer();

    void update(const std::vector<GPUMaterial>& materials) const;
    void bind(GLuint bindingPoint) const;

private:
    GLuint ssbo{};
};

class LightBuffer {
public:
    LightBuffer();
    ~LightBuffer();

    void update(const std::vector<int>& lightIndices) const;
    void bind(GLuint bindingPoint) const;

private:
    GLuint ssbo{};
};

typedef struct{
    int width, height;
} RaytracerDimensions;

typedef struct{
    glm::vec3 pos;
    glm::vec3 forward;
    glm::vec3 right;
    glm::vec3 up;
    float FOV;
    unsigned int frameCount;
} CameraParams;

typedef struct{
    glm::vec3 colorTop;
    glm::vec3 colorBottom;
} SkyParams;

void dispatchComputeShader(GLuint program, GLuint accumTexture, GLuint outputTexture,
    RaytracerDimensions raytracer_dimensions, CameraParams camera_params, SkyParams sky_params,
    size_t objectCount, int lightCount,
    int samplesPerFrame, int maxTotalSamples, uint32_t maxBounces);
