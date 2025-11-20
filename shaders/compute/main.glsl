#version 460 core
#extension GL_GOOGLE_include_directive: require

#include "camera.glsl"
#include "hittable.glsl"
#include "random.glsl"

layout (local_size_x = 16, local_size_y = 16) in;
layout (rgba32f, binding = 0) uniform image2D outputImage;

// Sky Rendering Parameters
uniform vec3 skyColorTop;
uniform vec3 skyColorBottom;

vec3 traceRay(vec3 rayOrigin, vec3 rayDir) {
    HitRecord rec;

    if (hitWorld(rayOrigin, rayDir, 0.001, INFINITY, rec)) {
        // Visualize Normal
        return 0.5 * (rec.normal + vec3(1.0));
    } else {
        // Blending factor: map ray.y from [-1, 1] to [0, 1]
        float blendingFactor = 0.5 * (rayDir.y + 1.0);
        return mix(skyColorBottom, skyColorTop, blendingFactor);
    }
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