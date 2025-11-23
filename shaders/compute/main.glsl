#version 460 core
#extension GL_GOOGLE_include_directive: require

#include "camera.glsl"
#include "hittable.glsl"
#include "random.glsl"
#include "material.glsl"

layout (local_size_x = 16, local_size_y = 16) in;
layout (rgba32f, binding = 0) uniform image2D outputImage;
layout (rgba32f, binding = 1) uniform image2D accumImage;

// Bloom Buffers
layout (rgba32f, binding = 4) uniform image2D outputBloom;
layout (rgba32f, binding = 5) uniform image2D accumBloom;

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

vec4 sampleTintSources(vec3 surfacePos, vec3 surfaceNormal, int ignoreObjIndex) {
    vec3 accumulatedTint = vec3(0.0);
    float totalInfluence = 0.0;

    for (int i = 0; i < objectCount; i++) {
        if (i == ignoreObjIndex) continue;

        GPUObject obj = objects[i];
        int matIndex = int(obj.data2.x);
        Material mat = materials[matIndex];

        if (mat.emissionMode == EMISSION_ABSOLUTE && mat.emissionStrength > 0.0) {

            vec3 targetCenter = obj.data1.xyz;
            float targetRadius = obj.data1.w;

            vec3 randomOffset = randomPointOnUnitSphere();
            vec3 targetPoint = targetCenter + (randomOffset * targetRadius);

            vec3 toLight = targetPoint - surfacePos;
            float distToTarget = length(toLight);
            vec3 L = toLight / distToTarget; // Normalized

            float NdotL = max(dot(surfaceNormal, L), 0.0);
            if (NdotL <= 0.0) continue;

            bool visible = false;

            // Start slightly off surface to avoid self-intersection
            vec3 currentOrigin = surfacePos + surfaceNormal * 0.001;

            // Trace 99% of the way to avoid hitting the emitter surface itself
            float remainingDist = distToTarget * 0.99;

            // Loop to handle transparent obstacles (Max 6 bounces)
            for (int k = 0; k < 6; k++) {
                HitRecord shadowRec;
                bool hit = hitWorld(currentOrigin, L, 0.001, remainingDist, shadowRec);

                if (!hit) {
                    visible = true;
                    break;
                }

                if (shadowRec.objIndex == i) {
                    visible = true;
                    break;
                }

                if (shadowRec.objIndex == ignoreObjIndex) {
                    currentOrigin = shadowRec.p + L * 0.001;
                    remainingDist -= shadowRec.t;
                    continue;
                }

                Material occMat = materials[shadowRec.matIndex];

                if (occMat.transmission > 0.01 || occMat.subsurface > 0.0) {
                    currentOrigin = shadowRec.p + L * 0.001;
                    remainingDist -= shadowRec.t;

                    if (remainingDist <= 0.001) {
                        visible = true;
                        break;
                    }
                } else {
                    visible = false;
                    break;
                }
            }

            if (visible) {
                float physicalDist = max(distance(surfacePos, targetCenter) - targetRadius, 0.0);

                // Falloff
                float attenuation = 1.0 / (1.0 + pow(physicalDist * 0.15f, 2.0f));
                float influence = mat.emissionStrength * attenuation * NdotL;
                influence = clamp(influence, 0.0, 1.0);

                accumulatedTint += mat.emission * influence;
                totalInfluence += influence;
            }
        }
    }

    return vec4(accumulatedTint, min(totalInfluence, 1.0));
}


vec3 sampleDirectLight(vec3 surfacePos, vec3 surfaceNormal, vec3 V, Material surfaceMat, int lightObjIndex) {
    GPUObject lightObj = objects[lightObjIndex];
    vec3 lightPos = lightObj.data1.xyz;
    float lightRadius = lightObj.data1.w;
    Material lightMat = materials[int(lightObj.data2.x)];

    if (lightMat.emissionMode == EMISSION_ABSOLUTE) return vec3(0.0);

    vec3 randomOnSphere = randomPointOnUnitSphere();
    vec3 lightSamplePos = lightPos + randomOnSphere * lightRadius;

    vec3 toLight = lightSamplePos - surfacePos;
    float distSq = dot(toLight, toLight);
    float dist = sqrt(distSq);
    vec3 L = normalize(toLight);

    float NdotL = dot(surfaceNormal, L);
    if (NdotL <= 0.0) return vec3(0.0);

    // Shadow Ray
    vec3 currentOrigin = surfacePos + surfaceNormal * 0.001;
    vec3 throughput = vec3(1.0);
    float remainingDist = dist - 0.01;
    bool visible = false;

    for (int i = 0; i < 5; i++) {
        HitRecord shadowRec;

        bool occluded = hitWorld(currentOrigin, L, 0.001, dist + 0.01, shadowRec);

        if (!occluded) {
            visible = true;
            break;
        }

        if (shadowRec.objIndex == lightObjIndex) {
            visible = true;
            break;
        }

        Material occMat = materials[shadowRec.matIndex];
        if (occMat.transmission > 0.01 || occMat.subsurface > 0.0) {
            throughput *= occMat.albedo;
            currentOrigin = shadowRec.p + L * 0.001;
            remainingDist -= shadowRec.t;
            if (remainingDist <= 0.0) break;
        } else {
            visible = false;
            break;
        }
    }

    if (!visible) return vec3(0.0);

    float lightArea = 4.0 * PI * lightRadius * lightRadius;
    float weight = lightArea / max(distSq, 0.001);

    vec3 lightRadiance = lightMat.emission * lightMat.emissionStrength * weight;
    vec3 brdf = evalBRDF(surfaceMat, surfaceNormal, V, L);

    return lightRadiance * brdf * throughput;
}

struct TraceResult {
    vec3 radiance;
    vec3 bloom;
};

TraceResult traceRay(vec3 rayOrigin, vec3 rayDir) {
    vec3 throughput = vec3(1.0);
    vec3 radiance = vec3(0.0);
    vec3 bloomRadiance = vec3(0.0);

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
            int channel = int(min(randomFloat() * 3.0, 2.0));
            float selectedDensity = sssSigmaT[channel];

            float distToScatter = -log(randomFloat()) / max(selectedDensity, 0.0001);

            if (distToScatter < distToBoundary) {
                currentOrigin += currentDir * distToScatter;


                // vec3 trReal = exp(-sssSigmaT * distToScatter);
                // float pdf = densityMax * exp(-densityMax * distToScatter);
                // vec3 weight = sssAlbedo * (trReal * densityMax / pdf); // Leads to explosion


                vec3 trReal = exp(-sssSigmaT * distToScatter);

                vec3 channelPDFs = sssSigmaT * trReal;
                float pdf = (channelPDFs.r + channelPDFs.g + channelPDFs.b) / 3.0;

                vec3 sigmaS = sssSigmaT * sssAlbedo;

                vec3 weight = (trReal * sigmaS) / max(pdf, 1e-8);

                throughput *= weight;

                throughput = min(throughput, vec3(10.0));

                currentDir = randomPointOnUnitSphere();
            } else {
                currentOrigin = rec.p;

                vec3 trReal = exp(-sssSigmaT * distToBoundary);

                vec3 channelExitProbs = exp(-sssSigmaT * distToBoundary);
                float pdfExit = (channelExitProbs.r + channelExitProbs.g + channelExitProbs.b) / 3.0;

                vec3 weight = trReal / max(pdfExit, 1e-8);
                throughput *= weight;

                throughput = min(throughput, vec3(10.0));

                Material mat = materials[rec.matIndex];
                vec3 outwardN = rec.frontFace ? rec.normal : -rec.normal;
                vec3 unitDir = normalize(currentDir);
                float eta = mat.ior;
                float cosTheta = min(dot(-unitDir, -outwardN), 1.0);
                float sinTheta = sqrt(max(0.0, 1.0 - cosTheta*cosTheta));

                if (eta * sinTheta > 1.0) {
                    // TIR
                    currentDir = normalize(-outwardN + randomPointOnUnitSphere());
                    currentOrigin -= outwardN * 0.001;
                } else {
                    currentDir = refractVec(unitDir, -outwardN, eta);
                    currentOrigin += outwardN * 0.001;
                    insideSSS = false;
                    lastPathWasSpecular = true;
                }
            }
            continue;
        }

        HitRecord rec;
        if (hitWorld(currentOrigin, currentDir, 0.001, INFINITY, rec)) {
            Material mat = materials[rec.matIndex];

            float effectiveBloomStr = (mat.bloomIntensity < 0.0) ? mat.emissionStrength : mat.bloomIntensity;

            if (mat.emissionMode == EMISSION_ABSOLUTE) {
                if (effectiveBloomStr > 0.0) {
                    vec3 filterDelta = mat.emission - vec3(1.0);
                    bloomRadiance += throughput * filterDelta * effectiveBloomStr;
                }
                throughput *= mat.emission * mat.emissionStrength;
                currentOrigin = rec.p + currentDir * 0.001;
                continue;
            }

            bool hitLight = false;
            for (int i = 0; i < lightCount; i++) {
                if (rec.objIndex == lightIndices[i]) { hitLight = true; break; }
            }

            if (hitLight || (mat.emissionStrength > 0.0 || effectiveBloomStr > 0.0)) {
                if (lastPathWasSpecular) {
                    radiance += throughput * mat.emission * mat.emissionStrength;
                    bloomRadiance += throughput * mat.emission * effectiveBloomStr;
                }
                break;
            }

            if (mat.emissionMode != EMISSION_ABSOLUTE) {
                vec4 tintData = sampleTintSources(rec.p, rec.normal, rec.objIndex);
                vec3 tintColor = tintData.rgb;
                float tintFactor = tintData.a;
                radiance += throughput * tintColor;
                bloomRadiance += throughput * tintColor;
                throughput *= (1.0 - tintFactor);
            }

            if (mat.subsurface > 0.0 && rec.frontFace) {
                vec3 f0 = calculateF0(mat.albedo, mat.metallic, mat.specularTint, mat.specular);
                vec3 fresnel = schlickFresnelRoughness(dot(rec.normal, -currentDir), f0, mat.roughness);
                float reflectProb = (fresnel.r + fresnel.g + fresnel.b) / 3.0;
                if (randomFloat() > reflectProb) {
                    insideSSS = true;
                    float radius = max(mat.subsurfaceRadius, 0.001);
                    sssSigmaT = vec3(1.0 / radius);
                    sssSigmaT += mat.absorption;
                    sssAlbedo = mat.albedo;
                    float eta = 1.0 / mat.ior;
                    currentDir = refractVec(currentDir, rec.normal, eta);
                    currentOrigin = rec.p - rec.normal * 0.001;
                    continue;
                }
            }

            bool skipNEE = mat.transmission > 0.01 || mat.subsurface > 0.0;
            if (!skipNEE && bounce < maxBounces - 1 && lightCount > 0) {
                vec3 V = -currentDir;
                for (int lightIdx = 0; lightIdx < lightCount; lightIdx++) {
                    vec3 directLight = sampleDirectLight(rec.p, rec.normal, V, mat, lightIndices[lightIdx]);
                    radiance += throughput * directLight;
                    bloomRadiance += throughput * directLight;
                }
            }

            vec3 attenuation;
            vec3 scattered;
            bool isSpecularBounce;
            if (scatter(mat, currentDir, rec, attenuation, scattered, isSpecularBounce)) {
                throughput *= attenuation;
                currentOrigin = rec.p;
                currentDir = scattered;
                if (isSpecularBounce) lastPathWasSpecular = true;
                else lastPathWasSpecular = skipNEE;

                if (bounce > 3) {
                    float p = max(throughput.r, max(throughput.g, throughput.b));
                    if (randomFloat() > p) break;
                    throughput /= p;
                }
            } else {
                break;
            }
        } else {
            vec3 sky = sampleSky(currentDir);
            radiance += throughput * sky;
            bloomRadiance += throughput * sky;
            break;
        }
    }
    return TraceResult(radiance, bloomRadiance);
}

void main()
{
    ivec2 pixelCoords = ivec2(gl_GlobalInvocationID.xy);
    if (pixelCoords.x >= int(resolution.x) || pixelCoords.y >= int(resolution.y)) return;

    vec4 prevVisual = imageLoad(accumImage, pixelCoords);
    vec4 prevBloom = imageLoad(accumBloom, pixelCoords);
    float currentSampleCount = prevVisual.a;

    if (currentSampleCount >= float(maxTotalSamples)) return;

    initRNG(uvec2(pixelCoords), frameCount);

    TraceResult result = { vec3(0.0), vec3(0.0) };

    for (int numSample = 0; numSample < samplesPerFrame; numSample ++) {
        vec2 jitter = vec2(randomFloat(), randomFloat());
        vec2 uv = (vec2(pixelCoords) + jitter) / resolution;
        vec2 ndc = uv * 2.0 - 1.0;
        float aspectRatio = resolution.x / resolution.y;
        ndc.x *= aspectRatio;
        float fovRadians = radians(cameraFOV);
        float planeScale = tan(fovRadians * 0.5);
        vec3 pixelTarget = cameraOrigin + (cameraForward + (ndc.x * planeScale * cameraRight) + (ndc.y * planeScale * cameraUp)) * focusDist;
        vec2 lensSample = randomPointInUnitDisk() * aperture * 0.5;
        vec3 rayOrigin = cameraOrigin + (cameraRight * lensSample.x) + (cameraUp * lensSample.y);
        vec3 rayDir = normalize(pixelTarget - rayOrigin);

        TraceResult sampleRes = traceRay(rayOrigin, rayDir);
        result.radiance += sampleRes.radiance;
        result.bloom += sampleRes.bloom;
    }

    if (isSafe(result.radiance) && isSafe(result.bloom)) {
        vec3 totalVisual = prevVisual.rgb + result.radiance;
        float totalSamples = currentSampleCount + float(samplesPerFrame);
        imageStore(accumImage, pixelCoords, vec4(totalVisual, totalSamples));

        vec3 totalBloom = prevBloom.rgb + result.bloom;
        imageStore(accumBloom, pixelCoords, vec4(totalBloom, totalSamples));

        vec3 finalVisual = totalVisual / totalSamples;
        vec3 finalBloom = totalBloom / totalSamples;

        imageStore(outputImage, pixelCoords, vec4(finalVisual, 1.0));
        imageStore(outputBloom, pixelCoords, vec4(finalBloom, 1.0));
    } else {
        imageStore(accumImage, pixelCoords, prevVisual);
        imageStore(accumBloom, pixelCoords, prevBloom);
    }
}