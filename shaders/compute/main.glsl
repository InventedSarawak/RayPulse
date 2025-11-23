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

// Samples a point on a spherical light source
// Returns the Light Color * BRDF * weighting
vec3 sampleDirectLight(vec3 surfacePos, vec3 surfaceNormal, vec3 V, Material surfaceMat, int lightObjIndex) {

    // 1. Get Light Data
    GPUObject lightObj = objects[lightObjIndex];
    vec3 lightPos = lightObj.data1.xyz;
    float lightRadius = lightObj.data1.w;
    Material lightMat = materials[int(lightObj.data2.x)];

    // 2. Pick a random point on the light (Uniform Area Sampling)
    vec3 randomOnSphere = randomPointOnUnitSphere();
    vec3 lightSamplePos = lightPos + randomOnSphere * lightRadius;

    // 3. Construct Light Vector (L)
    vec3 toLight = lightSamplePos - surfacePos;
    float distSq = dot(toLight, toLight);
    float dist = sqrt(distSq);
    vec3 L = normalize(toLight);

    // 4. Geometry Check: Is the light below the horizon?
    float NdotL = dot(surfaceNormal, L);
    if (NdotL <= 0.0) return vec3(0.0);

    // 5. Shadow Ray Cast
    // Offset slightly to avoid self-intersection acne
    HitRecord shadowRec;
    bool occluded = hitWorld(surfacePos + surfaceNormal * 0.001, L, 0.001, dist - 0.01, shadowRec);

    if (occluded) return vec3(0.0); // In shadow

    // 6. Calculate Light Intensity (Inverse Square Law)
    // Area of sphere = 4 * PI * r^2
    float lightArea = 4.0 * PI * lightRadius * lightRadius;

    // PDF (Probability Density Function) for area sampling: 1 / Area
    // Conversion to Solid Angle PDF: dist^2 / (cos(theta_light) * Area)
    // For a sphere, cos(theta_light) at the sampled point (normal pointing to center) is 1.0
    // Weight = 1 / PDF_solidAngle = Area / dist^2
    float weight = lightArea / max(distSq, 0.001);

    vec3 lightRadiance = lightMat.emission * lightMat.emissionStrength * weight;

    // 7. Calculate BRDF (Surface response) using accurate PBR evaluation
    vec3 brdf = evalBRDF(surfaceMat, surfaceNormal, V, L);

    return lightRadiance * brdf;
}


vec3 traceRay(vec3 rayOrigin, vec3 rayDir) {
    vec3 throughput = vec3(1.0);
    vec3 radiance = vec3(0.0);
    vec3 currentOrigin = rayOrigin;
    vec3 currentDir = rayDir;

    // Hardcoded logic to find the light (last object)
    // In a production engine, you would iterate a list of emissive objects
    int lightIndex = objectCount - 1;

    for (uint bounce = 0u; bounce < maxBounces; ++bounce) {
        HitRecord rec;

        if (hitWorld(currentOrigin, currentDir, 0.001, INFINITY, rec)) {
            Material mat = materials[rec.matIndex];

            // 1. EMISSION (Direct Hit)
            // -----------------------------------------------------------
            // If we hit the light by luck (indirect bounce), we must be careful.
            // If this is the FIRST bounce (bounce == 0), we keep it (so we can see the light source itself).
            // If it's a later bounce, we discard it because NEE already handled it
            // at the previous bounce (Double Counting prevention).
            // Exception: If the material is a mirror (roughness < 0.05), NEE didn't happen, so we keep it.
            bool isSpecular = mat.roughness < 0.05 || mat.transmission > 0.5;

            if (rec.objIndex == lightIndex) {
                // If we hit the light directly
                if (bounce == 0 || isSpecular) {
                    radiance += throughput * mat.emission * mat.emissionStrength;
                }
                // Stop tracing if we hit a light
                break;
            }

            // Other emissive objects (non-NEE lights)
            if (rec.objIndex != lightIndex && mat.emissionStrength > 0.0) {
                radiance += throughput * mat.emission * mat.emissionStrength;
            }

            // ===========================================================
            // BEER'S LAW (Volumetric Absorption)
            // ===========================================================
            if (!rec.frontFace && mat.transmission > 0.5) {
                vec3 absorption = mat.absorption;
                float distanceTraveled = rec.t;
                vec3 transmittance = exp(-absorption * distanceTraveled);
                throughput *= transmittance;
            }

            // ===========================================================
            // NEXT EVENT ESTIMATION (Direct Light Sampling)
            // ===========================================================
            // Only perform NEE on non-specular surfaces
            if (!isSpecular && bounce < maxBounces - 1) {
                vec3 V = -currentDir; // View direction is opposite to ray direction
                vec3 directLight = sampleDirectLight(rec.p, rec.normal, V, mat, lightIndex);
                radiance += throughput * directLight;
            }

            // 3. SCATTERING (Indirect Bounce)
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
        // 1. Accumulate
        vec3 totalSum = previousData.rgb + newColorSum;
        float totalSamples = currentSampleCount + float(samplesPerFrame);
        imageStore(accumImage, pixelCoords, vec4(totalSum, totalSamples));

        // 2. Calculate Average (Linear Space)
        vec3 finalColor = totalSum / totalSamples;

        // 3. Write directly to output (No Tone Mapping)
        imageStore(outputImage, pixelCoords, vec4(finalColor, 1.0));
    }
    else {
        // If we got a NaN, just write back the OLD data without changing it.
        imageStore(accumImage, pixelCoords, previousData);
    }
}