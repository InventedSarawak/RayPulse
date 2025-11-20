#version 460 core
#extension GL_GOOGLE_include_directive: require

#include "camera.glsl"
#include "hittable.glsl"
#include "random.glsl"
#include "material.glsl"

layout (local_size_x = 16, local_size_y = 16) in;
layout (rgba32f, binding = 0) uniform image2D outputImage;

// Sky Rendering Parameters
uniform vec3 skyColorTop;
uniform vec3 skyColorBottom;

vec3 sampleSky(vec3 rayDir) {
    float t = 0.5 * (rayDir.y + 1.0);
    return mix(skyColorBottom, skyColorTop, t);
}

vec3 traceRay(vec3 rayOrigin, vec3 rayDir) {
    vec3 throughput = vec3(1.0);  // Accumulated light attenuation
    vec3 radiance = vec3(0.0);     // Accumulated emitted light

    vec3 currentOrigin = rayOrigin;
    vec3 currentDir = rayDir;

    for (uint bounce = 0u; bounce < maxBounces; ++bounce) {
        HitRecord rec;

        if (hitWorld(currentOrigin, currentDir, 0.001, INFINITY, rec)) {
            // Fetch the material
            Material mat = materials[rec.matIndex];

            // Add emission from this surface
            // This is the KEY FIX: emissive materials contribute light at every bounce
            radiance += throughput * mat.emission;

            // Try to scatter the ray
            vec3 attenuation;
            vec3 scattered;

            if (scatter(mat, currentDir, rec, attenuation, scattered)) {
                // Ray scattered - update throughput and continue
                throughput *= attenuation;
                currentOrigin = rec.p;
                currentDir = scattered;

                // Russian Roulette path termination (optional but recommended)
                // Randomly terminate paths that contribute little
                if (bounce > 3) {
                    float maxComponent = max(throughput.r, max(throughput.g, throughput.b));
                    if (randomFloat() > maxComponent) {
                        break; // Terminate this path early
                    }
                    // Boost remaining paths to maintain energy conservation
                    throughput /= maxComponent;
                }
            } else {
                // Ray absorbed (hit a pure light source or was absorbed)
                break;
            }
        } else {
            // Ray escaped to sky
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

    initRNG(uvec2(pixelCoords), frameCount);

    vec3 colorAccumulator = vec3(0.0);

    for (int numSample = 0; numSample < samplesPerPixel; numSample ++) {
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

        colorAccumulator += traceRay(rayOrigin, rayDir);
    }

    // finalColor = pow(finalColor, vec3(1.0 / 2.2));
    vec3 finalColor = colorAccumulator / float(samplesPerPixel);

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

// Write the color to the output image
imageStore(outputImage, pixelCoords, vec4(finalColor, 1.0));
}