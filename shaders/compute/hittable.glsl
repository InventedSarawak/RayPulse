// --- CONSTANTS ---
#define TYPE_SPHERE 0
#define TYPE_PLANE 1
#define INFINITY 10000.0

// --- DATA STRUCTURES ---

struct HitRecord {
    float t;        // Distance along the ray
    vec3 p;         // World coordinate of the hit
    vec3 normal;    // Surface normal at that point
    bool frontFace; // Did the ray hit the outside?
    int matIndex;   // Material ID
    int objIndex;   // Object ID
};

// Fits exactly 32 bytes to match std430 alignment
struct GPUObject {
    // Data 1:
    // Sphere: xyz = center, w = radius
    // Plane:  xyz = normal, w = distance
    vec4 data1;

    // Data 2:
    // x = Material Index
    // w = Object Type ID (0=Sphere, 1=Plane)
    vec4 data2;
};

layout(std430, binding = 1) readonly buffer SceneBuffer {
    GPUObject objects[];
};

uniform int objectCount;


bool hitSphere(vec4 data1, vec4 data2, vec3 rayOrigin, vec3 rayDir, float tMin, float tMax, inout HitRecord rec) {
    vec3 center = data1.xyz;
    float radius = data1.w;

    vec3 oc = rayOrigin - center;
    float a = dot(rayDir, rayDir);
    float b = 2.0 * dot(oc, rayDir);
    float c = dot(oc, oc) - radius * radius;
    float discriminant = b * b - 4.0 * a * c;

    if (discriminant < 0.0) return false;
    float sqrtd = sqrt(discriminant);

    float root = (-b - sqrtd) / (2.0 * a);
    if (root <= tMin || root >= tMax) {
        root = (-b + sqrtd) / (2.0 * a);
        if (root <= tMin || root >= tMax) return false;
    }

    rec.t = root;
    rec.p = rayOrigin + rec.t * rayDir;
    vec3 outwardNormal = (rec.p - center) / radius;
    rec.frontFace = dot(rayDir, outwardNormal) < 0.0;
    rec.normal = rec.frontFace ? outwardNormal : -outwardNormal;
    rec.matIndex = int(data2.x);

    return true;
}

bool hitPlane(vec4 data1, vec4 data2, vec3 rayOrigin, vec3 rayDir, float tMin, float tMax, inout HitRecord rec) {
    vec3 normal = normalize(data1.xyz);
    float dist = data1.w;

    float denom = dot(normal, rayDir);

    // Check if ray is not parallel to plane (denom close to 0)
    if (abs(denom) > 1e-6) {
        float t = -(dot(rayOrigin, normal) + dist) / denom;
        if (t > tMin && t < tMax) {
            rec.t = t;
            rec.p = rayOrigin + t * rayDir;
            rec.frontFace = denom < 0.0;
            rec.normal = rec.frontFace ? normal : -normal;
            rec.matIndex = int(data2.x);
            return true;
        }
    }
    return false;
}


bool hitWorld(vec3 rayOrigin, vec3 rayDir, float tMin, float tMax, inout HitRecord rec) {
    HitRecord tempRec;
    bool hitAnything = false;
    float closestSoFar = tMax;

    for (int i = 0; i < objectCount; i++) {
        GPUObject obj = objects[i];
        int type = int(obj.data2.w);
        bool hit = false;

        // Polymorphic Dispatch based on Type Tag
        if (type == TYPE_SPHERE) {
            hit = hitSphere(obj.data1, obj.data2, rayOrigin, rayDir, tMin, closestSoFar, tempRec);
        }
        else if (type == TYPE_PLANE) {
            hit = hitPlane(obj.data1, obj.data2, rayOrigin, rayDir, tMin, closestSoFar, tempRec);
        }

        if (hit) {
            hitAnything = true;
            closestSoFar = tempRec.t;
            tempRec.objIndex = i;
            rec = tempRec;
        }
    }
    return hitAnything;
}