// Emission mode constants
#define EMISSION_PHYSICAL  0
#define EMISSION_ABSOLUTE  1

struct Material {
    vec3 albedo; float _pad0;
    vec3 emission; float emissionStrength;
    float roughness; float metallic; float transmission; float ior;
    vec3 specularTint; float specular;
    float clearcoat; float clearcoatRoughness; float subsurface; int emissionMode;
    vec3 absorption; float sheen;
    float subsurfaceRadius; float scatteringAnisotropy;
    float bloomIntensity;
    float _pad2;
};

layout(std430, binding = 2) readonly buffer MaterialBuffer {
    Material materials[];
};

float schlickFresnel(float cosine, float ior) {
    float r0 = (1.0 - ior) / (1.0 + ior);
    r0 = r0 * r0;
    return r0 + (1.0 - r0) * pow(max(0.0, 1.0 - cosine), 5.0);
}

vec3 randomCosineDirection() {
    float r1 = randomFloat();
    float r2 = randomFloat();
    float phi = 2.0 * PI * r1;
    float z = sqrt(1.0 - r2);
    float sinTheta = sqrt(r2);
    return vec3(sinTheta * cos(phi), sinTheta * sin(phi), z);
}

vec3 refractVec(vec3 uv, vec3 n, float etai_over_etat) {
    float cos_theta = min(dot(-uv, n), 1.0);
    vec3 r_out_perp = etai_over_etat * (uv + cos_theta * n);
    vec3 r_out_parallel = -sqrt(abs(1.0 - dot(r_out_perp, r_out_perp))) * n;
    return r_out_perp + r_out_parallel;
}

vec3 calculateF0(vec3 albedo, float metallic, vec3 specularTint, float specular) {
    vec3 dielectricF0 = 0.04 * specular * specularTint;
    vec3 metallicF0 = albedo;
    return mix(dielectricF0, metallicF0, metallic);
}

vec3 schlickFresnelRoughness(float cosine, vec3 f0, float roughness) {
    // The "1.0 - roughness" term dampens the grazing angle reflection
    return f0 + (max(vec3(1.0 - roughness), f0) - f0) * pow(max(0.0, 1.0 - cosine), 5.0);
}

vec3 sampleGGXMicrofacet(float roughness, vec3 N) {
    float a = roughness * roughness;
    float r1 = randomFloat();
    float r2 = randomFloat();
    float phi = 2.0 * PI * r1;
    float denom = 1.0 + (a * a - 1.0) * r2;
    float cosTheta = sqrt((1.0 - r2) / max(denom, 0.00001));
    float sinTheta = sqrt(1.0 - cosTheta * cosTheta);
    vec3 H = vec3(sinTheta * cos(phi), sinTheta * sin(phi), cosTheta);
    vec3 up = abs(N.z) < 0.999 ? vec3(0, 0, 1) : vec3(1, 0, 0);
    vec3 tangent = normalize(cross(up, N));
    vec3 bitangent = cross(N, tangent);
    return normalize(tangent * H.x + bitangent * H.y + N * H.z);
}

vec3 sampleCosineHemisphere(vec3 N) {
    vec3 randomDir = randomCosineDirection();
    vec3 up = abs(N.z) < 0.999 ? vec3(0, 0, 1) : vec3(1, 0, 0);
    vec3 tangent = normalize(cross(up, N));
    vec3 bitangent = cross(N, tangent);
    return normalize(tangent * randomDir.x + bitangent * randomDir.y + N * randomDir.z);
}

float clearcoatFresnel(float cosTheta) {
    const float clearcoatIOR = 1.5;
    float r0 = (1.0 - clearcoatIOR) / (1.0 + clearcoatIOR);
    r0 = r0 * r0;
    return r0 + (1.0 - r0) * pow(1.0 - cosTheta, 5.0);
}

vec3 sampleClearcoatLayer(float clearcoatRoughness, vec3 N) {
    float roughness = max(clearcoatRoughness, 0.01);
    return sampleGGXMicrofacet(roughness, N);
}

float clearcoatAttenuation(float clearcoat, float NdotV) {
    if (clearcoat < 0.01) return 1.0;
    float F = clearcoatFresnel(NdotV);
    float transmission = (1.0 - F);
    return mix(1.0, transmission, clearcoat);
}


bool scatter(Material mat, vec3 rayDir, HitRecord rec, out vec3 attenuation, out vec3 scattered, out bool isSpecularBounce) {
    vec3 N = rec.normal;
    vec3 V = -normalize(rayDir);

    if (mat.transmission > 0.01) {
        float refractionRatio = rec.frontFace ? (1.0 / mat.ior) : mat.ior;
        vec3 unitDir = normalize(rayDir);
        float cosTheta = min(dot(-unitDir, N), 1.0);
        float sin_theta = sqrt(max(0.0, 1.0 - cosTheta * cosTheta));
        bool cannotRefract = (refractionRatio * sin_theta) > 1.0;

        float reflectProb = schlickFresnel(cosTheta, refractionRatio);

        if (cannotRefract || randomFloat() < reflectProb) {
            scattered = reflect(unitDir, N);
        } else {
            scattered = refractVec(unitDir, N, refractionRatio);
        }

        attenuation = mat.albedo; // Tint the light
        isSpecularBounce = true;
        return true;
    }

    float NdotV = max(dot(N, V), 0.001);
    bool hasClearcoat = mat.clearcoat > 0.01;

    if (hasClearcoat) {
        float clearcoatF = clearcoatFresnel(NdotV);
        float clearcoatProb = clamp(mat.clearcoat * clearcoatF * 2.0, 0.0, 0.9);
        if (randomFloat() < clearcoatProb) {
            vec3 H = sampleClearcoatLayer(mat.clearcoatRoughness, N);
            scattered = reflect(-V, H);
            if (dot(scattered, N) <= 0.0) {
                scattered = reflect(-V, N);
                if (dot(scattered, N) <= 0.0) return false;
            }
            float HdotV = max(dot(H, V), 0.001);
            float F = clearcoatFresnel(HdotV);
            // Weight = F / Prob
            attenuation = vec3(F * mat.clearcoat / max(clearcoatProb, 0.001));
            isSpecularBounce = true;
            return true;
        }
    }

    vec3 f0 = calculateF0(mat.albedo, mat.metallic, mat.specularTint, mat.specular);
    vec3 fresnel = schlickFresnelRoughness(NdotV, f0, mat.roughness);
    float fresnelAvg = (fresnel.r + fresnel.g + fresnel.b) / 3.0;

    float specularProbability = fresnelAvg;

    specularProbability = mix(specularProbability, 1.0, mat.metallic);

    float roughnessFactor = 1.0 - mat.roughness;

    float selectionProbability = specularProbability;
    if (mat.metallic < 0.01) {
        selectionProbability *= (roughnessFactor * roughnessFactor); // Quadratic fade for smoother transition
    }

    selectionProbability = clamp(selectionProbability, 0.0, 1.0);

    if (randomFloat() < selectionProbability) {
        vec3 H = sampleGGXMicrofacet(mat.roughness, N);
        scattered = reflect(-V, H);

        if (dot(scattered, N) <= 0.0) {
            return false;
        }

        float HdotV = max(dot(H, V), 0.001);
        vec3 F = schlickFresnelRoughness(HdotV, f0, mat.roughness);

        // Weight = Energy / Probability
        // Energy = F (Fresnel Reflectance)
        // PDF = selectionProbability
        attenuation = F / max(selectionProbability, 0.001);
        isSpecularBounce = true;
    } else {
        scattered = sampleCosineHemisphere(N);
        vec3 diffuseColor = mat.albedo * (1.0 - mat.metallic);

        float diffuseProb = 1.0 - selectionProbability;

        // Energy Conservation:
        // Diffuse Energy = (1 - Fresnel) * Albedo
        float effectiveFresnel = fresnelAvg;
        if (mat.metallic < 0.01) {
            effectiveFresnel *= (roughnessFactor * roughnessFactor);
        }

        vec3 energyForDiffuse = vec3(1.0) - vec3(effectiveFresnel);

        // Weight = Energy / Probability
        attenuation = (diffuseColor * energyForDiffuse) / max(diffuseProb, 0.001);
        isSpecularBounce = false;
    }

    if (mat.sheen > 0.01 && mat.metallic < 0.9) {
        float sheenFactor = pow(1.0 - NdotV, 5.0);
        vec3 sheenColor = mix(vec3(1.0), mat.albedo, 0.5);
        attenuation += mat.sheen * sheenFactor * sheenColor;
    }

    if (hasClearcoat) {
        float transmission = clearcoatAttenuation(mat.clearcoat, NdotV);
        float clearcoatF = clearcoatFresnel(NdotV);
        float clearcoatProb = clamp(mat.clearcoat * clearcoatF * 2.0, 0.0, 0.9);
        attenuation *= transmission / max(1.0 - clearcoatProb, 0.001);
    }

    return true;
}

// NEE PBR Functions
float DistributionGGX(vec3 N, vec3 H, float roughness) {
    float a = roughness * roughness;
    float a2 = a * a;
    float NdotH = max(dot(N, H), 0.0);
    float NdotH2 = NdotH * NdotH;
    float num = a2;
    float denom = (NdotH2 * (a2 - 1.0) + 1.0);
    denom = PI * denom * denom;
    return num / max(denom, 0.0001);
}

float GeometrySchlickGGX(float NdotV, float roughness) {
    float r = (roughness + 1.0);
    float k = (r * r) / 8.0;
    float num = NdotV;
    float denom = NdotV * (1.0 - k) + k;
    return num / max(denom, 0.0001);
}

float GeometrySmith(vec3 N, vec3 V, vec3 L, float roughness) {
    float NdotV = max(dot(N, V), 0.0);
    float NdotL = max(dot(N, L), 0.0);
    float ggx2 = GeometrySchlickGGX(NdotV, roughness);
    float ggx1 = GeometrySchlickGGX(NdotL, roughness);
    return ggx1 * ggx2;
}

vec3 evalBRDF(Material mat, vec3 N, vec3 V, vec3 L) {
    if (mat.transmission > 0.5 || mat.roughness < 0.05) return vec3(0.0);

    vec3 H = normalize(V + L);
    float NdotV = max(dot(N, V), 0.001);
    float NdotL = max(dot(N, L), 0.001);

    vec3 F0 = calculateF0(mat.albedo, mat.metallic, mat.specularTint, mat.specular);
    float NDF = DistributionGGX(N, H, mat.roughness);
    float G = GeometrySmith(N, V, L, mat.roughness);

    vec3 F = schlickFresnelRoughness(max(dot(H, V), 0.0), F0, mat.roughness);

    vec3 numerator = NDF * G * F;
    float denominator = 4.0 * NdotV * NdotL;
    vec3 specular = numerator / max(denominator, 0.0001);

    vec3 kS = F;
    vec3 kD = vec3(1.0) - kS;
    kD *= (1.0 - mat.metallic);
    vec3 diffuse = kD * mat.albedo / PI;

    return (diffuse + specular) * NdotL;
}