uint pcg_hash(inout uint state) {
    uint state_curr = state * 747796405u + 2891336453u;
    uint word = ((state_curr >> ((state_curr >> 28u) + 4u)) ^ state_curr) * 277803737u;
    state = state_curr; // Update the state
    return (word >> 22u) ^ word;
}

uint rngState;

void initRNG(uvec2 pixelCoord, uint frame) {
    // Mix pixel coordinates and frame into a single seed
    uint seed = pixelCoord.x * 747796405u +
    pixelCoord.y * 2891336453u +
    frame * 277803737u;

    // Run the hash once to scramble the initial seed
    // (avoids patterns if seed values are sequential)
    rngState = seed;
    pcg_hash(rngState);
}

float randomFloat() {
    uint x = pcg_hash(rngState);

    // 0x3f800000u is the bit representation of 1.0
    // We mask the lower 23 bits of the random number (mantissa)
    // and OR it with the exponent for 1.0.
    uint floatBits = (x >> 9u) | 0x3f800000u;

    return uintBitsToFloat(floatBits) - 1.0;
}

float randomFloat(float min, float max) {
    return min + (max - min) * randomFloat();
}

vec3 randomPointOnUnitSphere() {
    float u = randomFloat();
    float v = randomFloat();
    float theta = 2.0 * 3.14159265 * u;
    float phi = acos(2.0 * v - 1.0);

    float x = sin(phi) * cos(theta);
    float y = sin(phi) * sin(theta);
    float z = cos(phi);
    return vec3(x, y, z);
}