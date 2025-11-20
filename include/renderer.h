#pragma once
#include <vector>
#include <glad/gl.h>
#include <glm/glm.hpp>

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
    OBJ_PLANE = 1
};

// The Generic GPU Object (32 bytes)
// Matches std430 layout: vec4, vec4
struct GPUObject {
    // Slot 1: Position (xyz) and a primary scalar (w)
    // For Sphere: Center(xyz), Radius(w)
    // For Plane:  Normal(xyz), Distance(w)
    glm::vec4 data1;

    // Slot 2: Secondary data (xyz) and Type ID (w)
    // For Sphere: Material(x), unused(yz), Type(w)
    // For Plane:  Material(x), unused(yz), Type(w)
    glm::vec4 data2;
};

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
    GLuint ssbo;
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

void dispatchComputeShader(GLuint program, GLuint texture, RaytracerDimensions raytracer_dimensions,
    CameraParams camera_params, SkyParams sky_params, size_t objectCount, int samplesPerPixel);