// Viewport Resolution
layout(location = 0) uniform vec2 resolution;

// Camera Basis Vectors
layout(location = 1) uniform vec3 cameraOrigin;
layout(location = 2) uniform vec3 cameraForward;
layout(location = 3) uniform vec3 cameraRight;
layout(location = 4) uniform vec3 cameraUp;
layout(location = 5) uniform float cameraFOV;

layout(location = 6) uniform uint frameCount;
layout(location = 7) uniform int samplesPerPixel;
layout(location = 8) uniform uint maxBounces;
