#version 460 core
#extension GL_GOOGLE_include_directive: require

#include "camera.glsl"
#include "hittable.glsl"
#include "random.glsl"
#include "material.glsl"

layout (local_size_x = 16, local_size_y = 16) in;
layout (rgba32f, binding = 0) uniform image2D outputImage;
layout (rgba32f, binding = 1) uniform image2D accumImage;

// Sky Rendering Parameters
uniform vec3 skyColorTop;
uniform vec3 skyColorBottom;

bool isSafe(vec3 v) {
    // Check if any component is NaN or Infinite
    if (isnan(v.x) || isnan(v.y) || isnan(v.z)) return false;
    if (isinf(v.x) || isinf(v.y) || isinf(v.z)) return false;
    return true;
}

vec3 sampleSky(vec3 rayDir) {
    float t = 0.5 * (rayDir.y + 1.0);
    return mix(skyColorBottom, skyColorTop, t);
}

vec4 sampleTintSources(vec3 surfacePos, vec3 surfaceNormal, int ignoreObjIndex) {
    vec3 accumulatedTint = vec3(0.0);
    float totalInfluence = 0.0;

    for (int i = 0; i < objectCount; i++) {
        if (i == ignoreObjIndex) continue;

        GPUObject obj = objects[i];
        Material mat = materials[int(obj.data2.x)];

        if (mat.emissionMode == EMISSION_ABSOLUTE && mat.emissionStrength > 0.0) {

            vec3 targetCenter = obj.data1.xyz;
            float targetRadius = obj.data1.w;

            vec3 randomOffset = randomPointOnUnitSphere();

            vec3 targetPoint = targetCenter + (randomOffset * targetRadius);

            vec3 toLight = targetPoint - surfacePos;
            float distToCenter = length(toLight);
            vec3 L = normalize(toLight);

            // Angle of Incidence (Lambert Law)
            float NdotL = max(dot(surfaceNormal, L), 0.0);

            // If facing away, no tint
            if (NdotL <= 0.0) continue;

            float distToSurface = distToCenter - targetRadius;

            if (distToSurface > 0.001) {
                HitRecord shadowRec;
                // Shadow Check
                bool occluded = hitWorld(surfacePos + surfaceNormal * 0.001, L, 0.001, distToSurface - 0.01, shadowRec);

                if (!occluded) {
                    // Magical Falloff
                    float attenuation = 1.0 / (1.0 + pow(distToSurface * 0.01f, 0.8f));

                    // Calculate Influence Factor (0.0 to 1.0)
                    // We clamp 'emissionStrength' logic so it acts as opacity.
                    float influence = mat.emissionStrength * attenuation * NdotL;

                    // Accumulate
                    accumulatedTint += mat.emission * influence;
                    totalInfluence += influence;
                }
            }
        }
    }

    // Clamp influence to 1.0 so we don't create negative light (black holes)
    return vec4(accumulatedTint, min(totalInfluence, 1.0));
}


vec3 traceRay(vec3 rayOrigin, vec3 rayDir) {
    vec3 throughput = vec3(1.0);
    vec3 radiance = vec3(0.0);
    vec3 currentOrigin = rayOrigin;
    vec3 currentDir = rayDir;

    for (uint bounce = 0u; bounce < maxBounces; ++bounce) {
        HitRecord rec;

        if (hitWorld(currentOrigin, currentDir, 0.001, INFINITY, rec)) {
            Material mat = materials[rec.matIndex];

            // ===========================================================
            // BEER'S LAW (Volumetric Absorption)
            // ===========================================================
            // If we hit a BACK face (!frontFace), and the material is transmissive,
            // it means the ray just traveled 'rec.t' distance THROUGH the medium.
            if (!rec.frontFace && mat.transmission > 0.5) {
                vec3 absorption = mat.absorption;
                float distanceTraveled = rec.t;

                // I = I₀ * exp(-absorption * distance)
                vec3 transmittance = exp(-absorption * distanceTraveled);
                throughput *= transmittance;
            }
            // ===========================================================


            // 1. DIRECT VISIBILITY (Emission)
            if (mat.emissionMode == EMISSION_ABSOLUTE) {
                radiance += throughput * mat.emission * mat.emissionStrength;
                break;
            }
            else if (mat.emissionMode == EMISSION_PHYSICAL && mat.emissionStrength > 0.0) {
                radiance += throughput * mat.emission * mat.emissionStrength;
            }

            // 2. INDIRECT TINTING (Color filters)
            if (mat.transmission < 0.5 && mat.metallic < 0.9) {
                vec4 tintData = sampleTintSources(rec.p, rec.normal, -1);
                vec3 tintColor = tintData.rgb;
                float tintFactor = tintData.a;
                radiance += throughput * tintColor;
                throughput *= (1.0 - tintFactor);
            }

            // 3. SCATTERING
            vec3 attenuation;
            vec3 scattered;
            if (scatter(mat, currentDir, rec, attenuation, scattered)) {
                throughput *= attenuation;
                currentOrigin = rec.p;
                currentDir = scattered;

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
    // Get the pixel coordinates for this thread
    ivec2 pixelCoords = ivec2(gl_GlobalInvocationID.xy);

    // Bounds check
    if (pixelCoords.x >= int(resolution.x) || pixelCoords.y >= int(resolution.y)) {
        return;
    }

    vec4 previousData = imageLoad(accumImage, pixelCoords);
    float currentSampleCount = previousData.a; // Sample count stored in alpha channel

    if (currentSampleCount >= float(maxTotalSamples)) return;

    initRNG(uvec2(pixelCoords), frameCount);

    vec3 newColorSum = vec3(0.0);

    for (int numSample = 0; numSample < samplesPerFrame; numSample ++) {
        // Add random jitter within the pixel [0, 1)
        vec2 jitter = vec2(randomFloat(), randomFloat());

        // Convert pixel coordinates to normalized device coordinates (NDC) [-1, 1]
        // Add 0.5 to sample at the pixel center + jitter
        vec2 uv = (vec2(pixelCoords) + jitter) / resolution; // [0, 1]
        vec2 ndc = uv * 2.0 - 1.0;                           // [-1, 1]

        // Adjust for aspect ratio
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

        // Update display buffer
        vec3 finalColor = totalSum / totalSamples;
        imageStore(outputImage, pixelCoords, vec4(finalColor, 1.0));
    }
    else {
        // If we got a NaN, just write back the OLD data without changing it.
        // This prevents the black pixel of death, effectively skipping this specific bad sample.
        imageStore(accumImage, pixelCoords, previousData);
    }

/*
    // Reference vector pointing down -Z
    vec3 refVector = vec3(0.0, 0.0, -1.0);

    // Calculate angle using dot product
    // dot(a,b) = |a||b|cos(theta) => theta = acos(dot(a,b)/(|a||b|)), |a|=|b|=1 since normalized
    float cosTheta = dot(rayDir, refVector);
    float angle = acos(cosTheta); // in radians

    float cornerDist = length(vec2(aspectRatio, 1.0)); // Distance from center in NDC space
    // Map angle to color
    // Angles range from 0 (center, parallel) to ~1.57 radians (90°, edges)
    float maxAngle = atan(cornerDist / 1.0); // FOV dependent max angle
    float t = clamp(angle / maxAngle, 0.0, 1.0);

    // Color gradient from blue (center) to red (edges)
    vec3 color1 = vec3(0.1, 0.1, 0.8); // Blue
    vec3 color2 = vec3(0.8, 0.1, 0.1); // Red
    vec3 color = mix(color1, color2, t);
*/
}