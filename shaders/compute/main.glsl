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

// --- NEE WITH TRANSPARENT SHADOWS ---
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

        // Check Transmission OR SSS (SSS objects allow light to pass through effectively)
        if (occMat.transmission > 0.01 || occMat.subsurface > 0.0) {
            // It is transparent/translucent!
            // Tint the shadow by the albedo
            throughput *= occMat.albedo;

            // Push ray past this surface and continue
            currentOrigin = shadowRec.p + L * 0.001;
            remainingDist -= shadowRec.t;

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

    return lightRadiance * brdf * throughput;
}

vec3 traceRay(vec3 rayOrigin, vec3 rayDir) {
    vec3 throughput = vec3(1.0);
    vec3 radiance = vec3(0.0);
    vec3 currentOrigin = rayOrigin;
    vec3 currentDir = rayDir;

    bool lastPathWasSpecular = true;

    bool insideSSS = false;
    vec3 sssSigmaT = vec3(0.0);
    vec3 sssAlbedo = vec3(0.0);

    for (uint bounce = 0u; bounce < maxBounces; ++bounce) {

        if (insideSSS) {
            HitRecord rec;
            bool hitBoundary = hitWorld(currentOrigin, currentDir, 0.001, INFINITY, rec);
            float distToBoundary = hitBoundary ? rec.t : INFINITY;

            // Sample distance using the MAX density (Color channel with highest absorption)
            float densityMax = max(sssSigmaT.r, max(sssSigmaT.g, sssSigmaT.b));
            float distToScatter = -log(randomFloat()) / max(densityMax, 0.0001);

            if (distToScatter < distToBoundary) {
                // --- SCATTER (Inside) ---
                currentOrigin += currentDir * distToScatter;

                // Weight = Transmittance / PDF
                // PDF = density * exp(-density * dist)
                // Transmittance (for this color channel) = exp(-sigma_t * dist)
                // We simplify this by just multiplying by Albedo, assuming densityMax is close enough,
                // but strictly we should adjust for colored density:
                // throughput *= sssAlbedo * (exp(-sssSigmaT * dist) / exp(-densityMax * dist));
                // For simplicity/stability, using just Albedo is common in simple tracers,
                // but let's add the spectral correction for colored glass SSS:

                vec3 trReal = exp(-sssSigmaT * distToScatter);
                float pdf = densityMax * exp(-densityMax * distToScatter);

                throughput *= sssAlbedo * (trReal * densityMax / pdf); // Simplifies to Albedo * correction
                // Correction reduces to: exp((densityMax - sssSigmaT) * dist)

                currentDir = randomPointOnUnitSphere();
            } else {
                // --- EXIT (Boundary) ---
                currentOrigin = rec.p;

                // MATH FIX:
                // We reached the boundary. The probability of this happening was:
                // Prob_Exit = exp(-densityMax * distToBoundary)
                // We must divide the actual physical transmittance by this probability
                // to effectively "cancel out" the survival bias.

                vec3 trReal = exp(-sssSigmaT * distToBoundary);
                float probExit = exp(-densityMax * distToBoundary);

                // Weigh the throughput
                throughput *= trReal / max(probExit, 1e-8);

                // Refract Out
                Material mat = materials[rec.matIndex];
                float ior = mat.ior;

                // Check Total Internal Reflection (TIR)
                // If exiting: n1=IOR, n2=1.0. Eta = IOR/1.0
                vec3 outwardN = rec.frontFace ? rec.normal : -rec.normal;
                vec3 unitDir = normalize(currentDir);
                float cosTheta = min(dot(-unitDir, -outwardN), 1.0);
                float sinTheta = sqrt(max(0.0, 1.0 - cosTheta*cosTheta));
                float eta = ior;

                if (eta * sinTheta > 1.0) {
                    // TIR: Reflect back inside
                    // OLD (Incorrect): Perfect mirror reflection causes hard "glowing edges"
                    // currentDir = reflect(unitDir, -outwardN);

                    // NEW (Correct): Scatter the ray back inside efficiently.
                    // Since we are inside a scattering volume, hitting a wall and reflecting
                    // is just another scattering event. We can treat it as a diffuse bounce
                    // off the inside wall, or just pick a random direction into the hemisphere.

                    // Simple fix: Randomize direction (Diffuse reflection back inside)
                    // We need a random direction in the hemisphere of -outwardN (inward)
                    currentDir = normalize(-outwardN + randomPointOnUnitSphere());

                    currentOrigin -= outwardN * 0.001; // Push back in
                } else {
                    // Refract Out
                    currentDir = refractVec(unitDir, -outwardN, eta);
                    currentOrigin += outwardN * 0.001;
                    insideSSS = false;
                    lastPathWasSpecular = true;
                }
            }
            continue;
        }

        // --- STANDARD SURFACE LOGIC ---
        HitRecord rec;
        if (hitWorld(currentOrigin, currentDir, 0.001, INFINITY, rec)) {
            Material mat = materials[rec.matIndex];

            // 1. CHECK FOR SSS ENTRY
            if (mat.subsurface > 0.0 && rec.frontFace) {
                vec3 f0 = calculateF0(mat.albedo, mat.metallic, mat.specularTint, mat.specular);
                vec3 fresnel = schlickFresnelRoughness(dot(rec.normal, -currentDir), f0, mat.roughness);
                float reflectProb = (fresnel.r + fresnel.g + fresnel.b) / 3.0;

                if (randomFloat() > reflectProb) {
                    insideSSS = true;
                    // Density = 1.0 / Radius
                    float radius = max(mat.subsurfaceRadius, 0.001);
                    sssSigmaT = vec3(1.0 / radius);
                    // If absorption is non-zero, add it to extinction coefficient
                    sssSigmaT += mat.absorption;

                    sssAlbedo = mat.albedo;

                    float eta = 1.0 / mat.ior;
                    currentDir = refractVec(currentDir, rec.normal, eta);
                    currentOrigin = rec.p - rec.normal * 0.001;
                    continue;
                }
            }

            // 2. EMISSION
            bool hitLight = false;
            for (int i = 0; i < lightCount; i++) {
                if (rec.objIndex == lightIndices[i]) { hitLight = true; break; }
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

            // 3. ABSORPTION
            if (!rec.frontFace && mat.transmission > 0.01) {
                vec3 absorption = mat.absorption;
                float distanceTraveled = rec.t;
                vec3 transmittance = exp(-absorption * distanceTraveled);
                throughput *= transmittance;
            }

            // 4. NEE DECISION
            bool skipNEE = mat.transmission > 0.01 || mat.subsurface > 0.0;

            // 5. NEE EXECUTION
            if (!skipNEE && bounce < maxBounces - 1 && lightCount > 0) {
                vec3 V = -currentDir;
                for (int lightIdx = 0; lightIdx < lightCount; lightIdx++) {
                    vec3 directLight = sampleDirectLight(rec.p, rec.normal, V, mat, lightIndices[lightIdx]);
                    radiance += throughput * directLight;
                }
            }

            // 6. SCATTERING
            vec3 attenuation;
            vec3 scattered;
            bool isSpecularBounce;

            if (scatter(mat, currentDir, rec, attenuation, scattered, isSpecularBounce)) {
                throughput *= attenuation;
                currentOrigin = rec.p;
                currentDir = scattered;

                if (isSpecularBounce) {
                    lastPathWasSpecular = true;
                } else {
                    lastPathWasSpecular = skipNEE;
                }

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