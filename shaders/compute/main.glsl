#version 460 core
#extension GL_GOOGLE_include_directive: require

#include "camera.glsl"
#include "hittable.glsl"
#include "random.glsl"
#include "material.glsl"

layout (local_size_x = 16, local_size_y = 16) in;
layout (rgba32f, binding = 0) uniform image2D outputImage;
layout (rgba32f, binding = 1) uniform image2D accumImage;

uniform vec3 skyColorTop;
uniform vec3 skyColorBottom;

bool isSafe(vec3 v) {
    if (isnan(v.x) || isnan(v.y) || isnan(v.z)) return false;
    if (isinf(v.x) || isinf(v.y) || isinf(v.z)) return false;
    return true;
}

vec3 sampleSky(vec3 rayDir) {
    float t = 0.5 * (rayDir.y + 1.0);
    return mix(skyColorBottom, skyColorTop, t);
}

// --- UPDATED NEE WITH TRANSPARENT SHADOWS ---
vec3 sampleDirectLight(vec3 surfacePos, vec3 surfaceNormal, vec3 V, Material surfaceMat, int lightObjIndex) {
    GPUObject lightObj = objects[lightObjIndex];
    vec3 lightPos = lightObj.data1.xyz;
    float lightRadius = lightObj.data1.w;
    Material lightMat = materials[int(lightObj.data2.x)];

    // 1. Pick a random point on the light
    vec3 randomOnSphere = randomPointOnUnitSphere();
    vec3 lightSamplePos = lightPos + randomOnSphere * lightRadius;

    vec3 toLight = lightSamplePos - surfacePos;
    float distSq = dot(toLight, toLight);
    float dist = sqrt(distSq);
    vec3 L = normalize(toLight);

    // Geometry check
    float NdotL = dot(surfaceNormal, L);
    if (NdotL <= 0.0) return vec3(0.0);

    // 2. SHADOW RAY LOOP (Transparent Shadows)
    vec3 currentOrigin = surfacePos + surfaceNormal * 0.001;
    vec3 throughput = vec3(1.0);
    float remainingDist = dist - 0.01;
    bool visible = false;

    // Allow passing through up to 5 transparent surfaces
    for (int i = 0; i < 5; i++) {
        HitRecord shadowRec;

        // Trace shadow ray
        bool occluded = hitWorld(currentOrigin, L, 0.001, remainingDist, shadowRec);

        if (!occluded) {
            visible = true; // Reached the light!
            break;
        }

        // We hit something. Check if it's transparent.
        Material occMat = materials[shadowRec.matIndex];

        if (occMat.transmission > 0.01) {
            // It is transparent!
            // Tint the shadow by the glass albedo (approximate)
            throughput *= occMat.albedo;

            // Push ray past this surface and continue
            currentOrigin = shadowRec.p + L * 0.001;
            remainingDist -= shadowRec.t;

            // Safety break if we ran out of distance (shouldn't happen if logic is sound)
            if (remainingDist <= 0.0) break;
        } else {
            // It's opaque. Light is blocked.
            visible = false;
            break;
        }
    }

    if (!visible) return vec3(0.0);

    // 3. Lighting Calculation
    float lightArea = 4.0 * PI * lightRadius * lightRadius;
    float weight = lightArea / max(distSq, 0.001);

    vec3 lightRadiance = lightMat.emission * lightMat.emissionStrength * weight;
    vec3 brdf = evalBRDF(surfaceMat, surfaceNormal, V, L);

    // Apply the transparent throughput to the final light contribution
    return lightRadiance * brdf * throughput;
}

vec3 traceRay(vec3 rayOrigin, vec3 rayDir) {
    vec3 throughput = vec3(1.0);
    vec3 radiance = vec3(0.0);
    vec3 currentOrigin = rayOrigin;
    vec3 currentDir = rayDir;

    bool lastPathWasSpecular = true;

    for (uint bounce = 0u; bounce < maxBounces; ++bounce) {
        HitRecord rec;

        if (hitWorld(currentOrigin, currentDir, 0.001, INFINITY, rec)) {
            Material mat = materials[rec.matIndex];

            // 1. EMISSION
            bool hitLight = false;
            for (int i = 0; i < lightCount; i++) {
                if (rec.objIndex == lightIndices[i]) {
                    hitLight = true;
                    break;
                }
            }

            if (hitLight) {
                if (lastPathWasSpecular) {
                    radiance += throughput * mat.emission * mat.emissionStrength;
                }
                break;
            }

            if (mat.emissionStrength > 0.0) {
                if (lastPathWasSpecular) {
                    radiance += throughput * mat.emission * mat.emissionStrength;
                }
            }

            // 2. ABSORPTION (Beer's Law)
            if (!rec.frontFace && mat.transmission > 0.01) {
                vec3 absorption = mat.absorption;
                float distanceTraveled = rec.t;
                vec3 transmittance = exp(-absorption * distanceTraveled);
                throughput *= transmittance;
            }

            // 3. NEE DECISION
            // We enable NEE for almost everything except perfect transmission/mirrors.
            // Rough glass *could* use NEE, but perfect glass cannot.
            bool skipNEE = mat.transmission > 0.01;

            // 4. NEE EXECUTION
            if (!skipNEE && bounce < maxBounces - 1 && lightCount > 0) {
                vec3 V = -currentDir;
                for (int lightIdx = 0; lightIdx < lightCount; lightIdx++) {
                    vec3 directLight = sampleDirectLight(rec.p, rec.normal, V, mat, lightIndices[lightIdx]);
                    radiance += throughput * directLight;
                }
            }

            // 5. SCATTERING
            vec3 attenuation;
            vec3 scattered;
            bool isSpecularBounce;

            if (scatter(mat, currentDir, rec, attenuation, scattered, isSpecularBounce)) {
                throughput *= attenuation;
                currentOrigin = rec.p;
                currentDir = scattered;

                // MIS Logic:
                // If we took a Specular path (Reflection/Refraction), NEE didn't account for it.
                // So we must accept Implicit hits (lastPathWasSpecular = true).
                // If we took a Diffuse path, NEE handled it, UNLESS we skipped NEE.
                if (isSpecularBounce) {
                    lastPathWasSpecular = true;
                } else {
                    lastPathWasSpecular = skipNEE;
                }

                // Russian Roulette
                if (bounce > 3) {
                    float p = max(throughput.r, max(throughput.g, throughput.b));
                    if (randomFloat() > p) break;
                    throughput /= p;
                }
            } else {
                break;
            }
        } else {
            radiance += throughput * sampleSky(currentDir);
            break;
        }
    }
    return radiance;
}

void main()
{
    ivec2 pixelCoords = ivec2(gl_GlobalInvocationID.xy);

    if (pixelCoords.x >= int(resolution.x) || pixelCoords.y >= int(resolution.y)) {
        return;
    }

    vec4 previousData = imageLoad(accumImage, pixelCoords);
    float currentSampleCount = previousData.a;

    if (currentSampleCount >= float(maxTotalSamples)) return;

    initRNG(uvec2(pixelCoords), frameCount);

    vec3 newColorSum = vec3(0.0);

    for (int numSample = 0; numSample < samplesPerFrame; numSample ++) {
        vec2 jitter = vec2(randomFloat(), randomFloat());
        vec2 uv = (vec2(pixelCoords) + jitter) / resolution;
        vec2 ndc = uv * 2.0 - 1.0;

        float aspectRatio = resolution.x / resolution.y;
        ndc.x *= aspectRatio;

        float fovRadians = radians(cameraFOV);
        float planeScale = tan(fovRadians * 0.5);

        vec3 rayOrigin = cameraOrigin;
        vec3 rayDir = normalize(cameraForward +
                                (ndc.x * planeScale * cameraRight) +
                                (ndc.y * planeScale * cameraUp));

        newColorSum += traceRay(rayOrigin, rayDir);
    }

    if (isSafe(newColorSum)) {
        vec3 totalSum = previousData.rgb + newColorSum;
        float totalSamples = currentSampleCount + float(samplesPerFrame);
        imageStore(accumImage, pixelCoords, vec4(totalSum, totalSamples));
        vec3 finalColor = totalSum / totalSamples;
        imageStore(outputImage, pixelCoords, vec4(finalColor, 1.0));
    }
    else {
        imageStore(accumImage, pixelCoords, previousData);
    }
}