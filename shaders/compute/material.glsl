// Material type constants
#define MAT_LAMBERTIAN    0
#define MAT_METAL         1
#define MAT_DIELECTRIC    2
#define MAT_EMISSIVE      3
#define MAT_PLASTIC       4
#define MAT_CLEARCOAT     5

// Texture slot indices (-1 = no texture)
struct TextureIndices {
    int albedo;        // Base color / diffuse
    int normal;        // Normal map
    int roughness;     // Roughness map
    int metallic;      // Metallic map
    int emission;      // Emission map
};

// Unified material descriptor (64 bytes, cache-friendly)
struct Material {
    // Color properties (16 bytes)
    vec3 albedo;           // Base color
    float _pad0;

    // Physical properties (16 bytes)
    vec3 emission;         // Emitted light
    float ior;             // Index of refraction (1.0 = air, 1.5 = glass, 2.4 = diamond)

    // Surface properties (16 bytes)
    float roughness;       // 0 = mirror, 1 = diffuse
    float metallic;        // 0 = dielectric, 1 = metal
    float specular;        // Specular reflection strength (0-1)
    float transmission;    // 0 = opaque, 1 = transparent

    // Material behavior (16 bytes)
    int type;              // Primary material type
    float subsurface;      // Subsurface scattering amount
    float clearcoat;       // Clearcoat layer strength
    float sheen;           // Fabric-like reflection

    // Texture indices - stored as packed ints in unused space
    // TO be implemented later
};

layout(std430, binding = 2) readonly buffer MaterialBuffer {
    Material materials[];
};

float schlickFresnel(float cosine, float ior) {
    float r0 = (1.0 - ior) / (1.0 + ior);
    r0 = r0 * r0;
    return r0 + (1.0 - r0) * pow(1.0 - cosine, 5.0);
}

// Sample hemisphere with cosine-weighted distribution (Lambertian)
vec3 randomCosineDirection() {
    float r1 = randomFloat();
    float r2 = randomFloat();

    float phi = 2.0 * 3.14159265359 * r1;
    float z = sqrt(1.0 - r2);
    float sinTheta = sqrt(r2);

    return vec3(sinTheta * cos(phi), sinTheta * sin(phi), z);
}

// GGX microfacet distribution (for rough surfaces)
vec3 sampleGGX(float roughness, vec3 N) {
    float a = roughness * roughness;
    float r1 = randomFloat();
    float r2 = randomFloat();

    float phi = 2.0 * 3.14159265359 * r1;
    float cosTheta = sqrt((1.0 - r2) / (1.0 + (a * a - 1.0) * r2));
    float sinTheta = sqrt(1.0 - cosTheta * cosTheta);

    // Spherical to Cartesian
    vec3 H = vec3(sinTheta * cos(phi), sinTheta * sin(phi), cosTheta);

    // Transform to world space around N
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

bool scatter(Material mat, vec3 rayDir, HitRecord rec, out vec3 attenuation, out vec3 scattered) {
    vec3 N = rec.normal;

    // Dispatch based on material type
    if (mat.type == MAT_LAMBERTIAN) {
        // Diffuse scattering
        vec3 scatterDir = N + randomCosineDirection();

        // Catch degenerate scatter direction
        if (abs(scatterDir.x) < 1e-8 && abs(scatterDir.y) < 1e-8 && abs(scatterDir.z) < 1e-8) {
            scatterDir = N;
        }

        scattered = normalize(scatterDir);
        attenuation = mat.albedo;
        return true;
    }

    else if (mat.type == MAT_METAL) {
        // Reflection with roughness
        vec3 reflected = reflect(rayDir, N);

        if (mat.roughness > 0.01) {
            // Sample microfacet normal based on roughness
            vec3 microfacetN = sampleGGX(mat.roughness, N);
            scattered = reflect(rayDir, microfacetN);
        } else {
            scattered = reflected;
        }

        attenuation = mat.albedo;
        return dot(scattered, N) > 0.0; // Absorbed if scattered into surface
    }

    else if (mat.type == MAT_DIELECTRIC) {
        attenuation = vec3(1.0);

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

        return true;
    }

    else if (mat.type == MAT_EMISSIVE) {
        if (length(mat.emission) > 10.0) {
            return false; // Pure light source, no scattering
        }

        vec3 scatterDir = N + randomCosineDirection();

        if (abs(scatterDir.x) < 1e-8 && abs(scatterDir.y) < 1e-8 && abs(scatterDir.z) < 1e-8) {
            scatterDir = N;
        }

        scattered = normalize(scatterDir);
        attenuation = mat.albedo; // Emissive surfaces can have colored surfaces too
        return true;
    }

    else if (mat.type == MAT_PLASTIC) {
        // Plastic = mix of specular and diffuse
        float fresnelTerm = schlickFresnel(abs(dot(rayDir, N)), mat.ior);

        if (randomFloat() < mat.specular * fresnelTerm) {
            // Specular reflection (like metal but weaker)
            vec3 microfacetN = sampleGGX(mat.roughness, N);
            scattered = reflect(rayDir, microfacetN);
            attenuation = vec3(1.0); // White specular highlight
            return dot(scattered, N) > 0.0;
        } else {
            // Diffuse scattering
            scattered = normalize(N + randomCosineDirection());
            attenuation = mat.albedo;
            return true;
        }
    }

    else if (mat.type == MAT_CLEARCOAT) {
        // Two-layer material: glossy coat over diffuse base
        float fresnelTerm = schlickFresnel(abs(dot(rayDir, N)), mat.ior);

        if (randomFloat() < mat.clearcoat * fresnelTerm) {
            // Scatter from clearcoat layer (glossy reflection)
            vec3 microfacetN = sampleGGX(0.05, N); // Clearcoat is always glossy
            scattered = reflect(rayDir, microfacetN);
            attenuation = vec3(1.0);
            return dot(scattered, N) > 0.0;
        } else {
            // Scatter from base layer (diffuse)
            scattered = normalize(N + randomCosineDirection());
            attenuation = mat.albedo;
            return true;
        }
    }

    // Fallback (shouldn't reach here)
    return false;
}
