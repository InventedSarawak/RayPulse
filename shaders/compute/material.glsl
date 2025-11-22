// Emission mode constants
#define EMISSION_PHYSICAL  0
#define EMISSION_ABSOLUTE  1

// Unified material descriptor (112 bytes, std430 aligned)
// MATCHES C++ struct GPUMaterial exactly
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

    // Block 7: Advanced / Padding (16 bytes)
    // These were missing in your GLSL, causing misalignment!
    float subsurfaceRadius;
    float scatteringAnisotropy;
    float _pad1;
    float _pad2;
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

// Renamed to avoid collision with GLSL built-in refract()
vec3 refractVec(vec3 uv, vec3 n, float etai_over_etat) {
    float cos_theta = min(dot(-uv, n), 1.0);
    vec3 r_out_perp = etai_over_etat * (uv + cos_theta * n);
    vec3 r_out_parallel = -sqrt(abs(1.0 - dot(r_out_perp, r_out_perp))) * n;
    return r_out_perp + r_out_parallel;
}

// Calculate F0 (base reflectance at normal incidence)
vec3 calculateF0(vec3 albedo, float metallic, vec3 specularTint, float specular) {
    // Dielectric F0 (typically 0.04 for common materials, modulated by specular param)
    vec3 dielectricF0 = 0.04 * specular * specularTint;

    // Metallic F0 (uses albedo as base reflectance)
    vec3 metallicF0 = albedo;

    // Blend based on metallic parameter
    return mix(dielectricF0, metallicF0, metallic);
}

vec3 schlickFresnelVec(float cosine, vec3 f0) {
    return f0 + (vec3(1.0) - f0) * pow(1.0 - cosine, 5.0);
}

// Sample a microfacet normal weighted by GGX distribution
vec3 sampleGGXMicrofacet(float roughness, vec3 N) {
    float a = roughness * roughness;
    float r1 = randomFloat();
    float r2 = randomFloat();

    float phi = 2.0 * 3.14159265359 * r1;
    float cosTheta = sqrt((1.0 - r2) / (1.0 + (a * a - 1.0) * r2));
    float sinTheta = sqrt(1.0 - cosTheta * cosTheta);

    // Tangent space vector
    vec3 H = vec3(sinTheta * cos(phi), sinTheta * sin(phi), cosTheta);

    // Transform to world space
    vec3 up = abs(N.z) < 0.999 ? vec3(0, 0, 1) : vec3(1, 0, 0);
    vec3 tangent = normalize(cross(up, N));
    vec3 bitangent = cross(N, tangent);

    return normalize(tangent * H.x + bitangent * H.y + N * H.z);
}

// Cosine-weighted hemisphere sampling
vec3 sampleCosineHemisphere(vec3 N) {
    vec3 randomDir = randomCosineDirection();

    // Build TBN matrix
    vec3 up = abs(N.z) < 0.999 ? vec3(0, 0, 1) : vec3(1, 0, 0);
    vec3 tangent = normalize(cross(up, N));
    vec3 bitangent = cross(N, tangent);

    return normalize(tangent * randomDir.x + bitangent * randomDir.y + N * randomDir.z);
}

// Calculate clearcoat fresnel (uses fixed IOR for coatings)
float clearcoatFresnel(float cosTheta) {
    // Typical clearcoat IOR is ~1.5 (polyurethane, acrylic)
    const float clearcoatIOR = 1.5;
    float r0 = (1.0 - clearcoatIOR) / (1.0 + clearcoatIOR);
    r0 = r0 * r0;
    return r0 + (1.0 - r0) * pow(1.0 - cosTheta, 5.0);
}

// Sample the clearcoat layer (separate from base roughness)
vec3 sampleClearcoatLayer(float clearcoatRoughness, vec3 N) {
    // Clearcoat is typically much smoother than the base
    // Clamp minimum roughness to avoid numerical issues
    float roughness = max(clearcoatRoughness, 0.01);
    return sampleGGXMicrofacet(roughness, N);
}

// Calculate how much light reaches the base layer
// (accounts for energy stolen by clearcoat reflection)
float clearcoatAttenuation(float clearcoat, float NdotV) {
    if (clearcoat < 0.01) return 1.0;

    float F = clearcoatFresnel(NdotV);
    // Energy that transmits through: (1 - F)
    // Squared because light goes down AND back up
    float transmission = (1.0 - F);

    // Blend based on clearcoat strength
    return mix(1.0, transmission, clearcoat);
}



bool scatter(Material mat, vec3 rayDir, HitRecord rec, out vec3 attenuation, out vec3 scattered) {
    vec3 N = rec.normal;
    vec3 V = -normalize(rayDir);

    // ============================================
    // TRANSMISSION PATH
    // ============================================
    if (mat.transmission > 0.5) {
        float refractionRatio = rec.frontFace ? (1.0 / mat.ior) : mat.ior;
        vec3 unitDir = normalize(rayDir);

        float cosTheta = min(dot(-unitDir, N), 1.0);
        float sin_theta = sqrt(1.0 - cosTheta * cosTheta);

        bool cannotRefract = (refractionRatio * sin_theta) > 1.0;
        float reflectProb = schlickFresnel(cosTheta, refractionRatio);

        if (cannotRefract || randomFloat() < reflectProb) {
            scattered = reflect(unitDir, N);
        } else {
            scattered = refractVec(unitDir, N, refractionRatio);
        }

        attenuation = mat.albedo;
        return true;
    }

    float NdotV = max(dot(N, V), 0.001);
    bool hasClearcoat = mat.clearcoat > 0.01;

    // ============================================
    // CLEARCOAT LAYER
    // ============================================
    if (hasClearcoat) {
        float clearcoatF = clearcoatFresnel(NdotV);
        float clearcoatProb = clamp(mat.clearcoat * clearcoatF * 2.0, 0.0, 0.9);

        if (randomFloat() < clearcoatProb) {
            vec3 H = sampleClearcoatLayer(mat.clearcoatRoughness, N);
            scattered = reflect(-V, H);

            if (dot(scattered, N) <= 0.0) {
                scattered = reflect(-V, N);
                if (dot(scattered, N) <= 0.0) {
                    return false;
                }
            }

            float HdotV = max(dot(H, V), 0.001);
            float F = clearcoatFresnel(HdotV);
            attenuation = vec3(F * mat.clearcoat / max(clearcoatProb, 0.001));

            return true;
        }
    }

    // ============================================
    // BASE LAYER
    // ============================================

    vec3 f0 = calculateF0(mat.albedo, mat.metallic, mat.specularTint, mat.specular);
    vec3 fresnel = schlickFresnelVec(NdotV, f0);
    float fresnelAvg = (fresnel.r + fresnel.g + fresnel.b) / 3.0;

    // Calculate specular probability
    float specularProbability = fresnelAvg;
    specularProbability = mix(specularProbability, 1.0, mat.metallic);

    // 3. Roughness Dampening (The Fix)
    // For Dielectrics (Metallic=0):
    //   If roughness = 1.0, we want specularProbability to be 0.0 (Pure Diffuse).
    //   If roughness = 0.0, we want specularProbability to equal Fresnel (Shiny Plastic).
    // For Metals:
    //   Roughness generally doesn't kill the energy, just spreads it. We keep it 1.0.

    float roughnessDampener = mix(1.0 - mat.roughness, 1.0, mat.metallic);
    specularProbability *= roughnessDampener;
    // Correct: Uses float '0.0' and '1.0'
    specularProbability = clamp(specularProbability, 0.0, 1.0);

    // ============================================
    // LOBE SELECTION
    // ============================================

    if (randomFloat() < specularProbability) {
        // --- SPECULAR LOBE ---
        vec3 H = sampleGGXMicrofacet(mat.roughness, N);
        scattered = reflect(-V, H);

        if (dot(scattered, N) <= 0.0) {
            scattered = reflect(-V, N);
            if (dot(scattered, N) <= 0.0) {
                return false;
            }
        }

        float HdotV = max(dot(H, V), 0.001);
        vec3 F = schlickFresnelVec(HdotV, f0);

        // Fresnel term only (probability handled by branching)
        attenuation = F;

    } else {
        // --- DIFFUSE LOBE ---
        scattered = sampleCosineHemisphere(N);

        vec3 diffuseColor = mat.albedo * (1.0 - mat.metallic);

        // OLD: Assumed reflection always happened
        // attenuation = diffuseColor * (1.0 - fresnelAvg);

        // NEW: Only subtract the energy that was actually diverted to specular
        // Uses the same 'roughnessDampener' you calculated earlier
        attenuation = diffuseColor * (1.0 - (fresnelAvg * roughnessDampener));
    }

    // ============================================
    // ADD SHEEN (always, for non-metals)
    // ============================================
    if (mat.sheen > 0.01 && mat.metallic < 0.9) {
        float sheenFactor = pow(1.0 - NdotV, 5.0);
        vec3 sheenColor = mix(vec3(1.0), mat.albedo, 0.5);
        attenuation += mat.sheen * sheenFactor * sheenColor;
    }

    // ============================================
    // CLEARCOAT ATTENUATION
    // ============================================
    if (hasClearcoat) {
        float transmission = clearcoatAttenuation(mat.clearcoat, NdotV);
        float clearcoatF = clearcoatFresnel(NdotV);
        float clearcoatProb = clamp(mat.clearcoat * clearcoatF * 2.0, 0.0, 0.9);
        float baseProb = 1.0 - clearcoatProb;

        attenuation *= transmission / max(baseProb, 0.001);
    }

    return true;
}