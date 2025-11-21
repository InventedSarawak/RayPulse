// Emission mode constants
#define EMISSION_PHYSICAL  0
#define EMISSION_ABSOLUTE  1

// Unified material descriptor (96 bytes, std430 aligned)
struct Material {
    // Block 1: Color (16 bytes)
    vec3 albedo;
    float _pad0;

    // Block 2: Emission (16 bytes)
    vec3 emission;
    float emissionStrength;

    // Block 3: Surface (16 bytes)
    float roughness;
    float metallic;
    float transmission;
    float ior;

    // Block 4: Specular (16 bytes)
    vec3 specularTint;
    float specular;

    // Block 5: Coating (16 bytes)
    float clearcoat;
    float clearcoatRoughness;
    float subsurface;
    int emissionMode;

    // Block 6: Volumetric (16 bytes)
    vec3 absorption;
    float sheen;
};

layout(std430, binding = 2) readonly buffer MaterialBuffer {
    Material materials[];
};

// Fresnel approximation
float schlickFresnel(float cosine, float ior) {
    float r0 = (1.0 - ior) / (1.0 + ior);
    r0 = r0 * r0;
    return r0 + (1.0 - r0) * pow(1.0 - cosine, 5.0);
}

// Sample hemisphere with cosine-weighted distribution
vec3 randomCosineDirection() {
    float r1 = randomFloat();
    float r2 = randomFloat();

    float phi = 2.0 * 3.14159265359 * r1;
    float z = sqrt(1.0 - r2);
    float sinTheta = sqrt(r2);

    return vec3(sinTheta * cos(phi), sinTheta * sin(phi), z);
}

// GGX microfacet distribution
vec3 sampleGGX(float roughness, vec3 N) {
    float a = roughness * roughness;
    float r1 = randomFloat();
    float r2 = randomFloat();

    float phi = 2.0 * 3.14159265359 * r1;
    float cosTheta = sqrt((1.0 - r2) / (1.0 + (a * a - 1.0) * r2));
    float sinTheta = sqrt(1.0 - cosTheta * cosTheta);

    vec3 H = vec3(sinTheta * cos(phi), sinTheta * sin(phi), cosTheta);

    vec3 up = abs(N.z) < 0.999 ? vec3(0, 0, 1) : vec3(1, 0, 0);
    vec3 tangent = normalize(cross(up, N));
    vec3 bitangent = cross(N, tangent);

    return normalize(tangent * H.x + bitangent * H.y + N * H.z);
}

vec3 refract(vec3 uv, vec3 n, float etai_over_etat) {
    float cos_theta = min(dot(-uv, n), 1.0);
    vec3 r_out_perp = etai_over_etat * (uv + cos_theta * n);
    vec3 r_out_parallel = -sqrt(abs(1.0 - dot(r_out_perp, r_out_perp))) * n;
    return r_out_perp + r_out_parallel;
}

// Simplified scatter function for initial implementation
bool scatter(Material mat, vec3 rayDir, HitRecord rec, out vec3 attenuation, out vec3 scattered) {
    vec3 N = rec.normal;

    // For now, implement basic behaviors based on material parameters

    // Pure transmission (glass-like)
    if (mat.transmission > 0.5) {
        float refractionRatio = rec.frontFace ? (1.0 / mat.ior) : mat.ior;
        vec3 unitDir = normalize(rayDir);

        float cos_theta = min(dot(-unitDir, N), 1.0);
        float sin_theta = sqrt(1.0 - cos_theta * cos_theta);
        bool cannot_refract = (refractionRatio * sin_theta) > 1.0;
        float reflectProb = schlickFresnel(cos_theta, refractionRatio);

        if (cannot_refract || randomFloat() < reflectProb) {
            scattered = reflect(unitDir, N);
        } else {
            scattered = refract(unitDir, N, refractionRatio);
        }

        attenuation = mat.albedo;
        return true;
    }

    // Metallic reflection
    if (mat.metallic > 0.5) {
        vec3 reflected = reflect(rayDir, N);

        if (mat.roughness > 0.01) {
            vec3 microfacetN = sampleGGX(mat.roughness, N);
            scattered = reflect(rayDir, microfacetN);
        } else {
            scattered = reflected;
        }

        attenuation = mat.albedo;
        return dot(scattered, N) > 0.0;
    }

    // Diffuse (Lambertian)
    vec3 scatterDir = N + randomCosineDirection();

    if (abs(scatterDir.x) < 1e-8 && abs(scatterDir.y) < 1e-8 && abs(scatterDir.z) < 1e-8) {
        scatterDir = N;
    }

    scattered = normalize(scatterDir);
    attenuation = mat.albedo;
    return true;
}