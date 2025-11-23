// --- CONSTANTS ---
#define TYPE_SPHERE 0
#define TYPE_PLANE 1
#define TYPE_CUBE 2
#define TYPE_CYLINDER 3
#define TYPE_CONE 4
#define TYPE_PYRAMID 5
#define TYPE_TETRAHEDRON 6
#define TYPE_PRISM 7
#define TYPE_DODECAHEDRON 8
#define TYPE_ICOSAHEDRON 9

#define INFINITY 10000.0
#define PI 3.1415926535

struct HitRecord {
    float t;
    vec3 p;
    vec3 normal;
    bool frontFace;
    int matIndex;
    int objIndex;
};

struct GPUObject {
    vec4 data1; // Center(xyz), BoundingRadius(w)
    vec4 data2; // Rotation(xyz), Material(w)
    vec4 data3; // Scale(xyz), Type(w)
    vec4 data4; // Padding
};

layout(std430, binding = 1) readonly buffer SceneBuffer {
    GPUObject objects[];
};

layout(std430, binding = 3) readonly buffer LightBuffer {
    int lightIndices[];
};

uniform int objectCount;


mat3 buildRotationMatrix(vec3 rotEuler) {
    vec3 rad = radians(rotEuler);
    float cx = cos(rad.x), sx = sin(rad.x);
    float cy = cos(rad.y), sy = sin(rad.y);
    float cz = cos(rad.z), sz = sin(rad.z);
    mat3 rx = mat3(1, 0, 0, 0, cx, sx, 0, -sx, cx);
    mat3 ry = mat3(cy, 0, -sy, 0, 1, 0, sy, 0, cy);
    mat3 rz = mat3(cz, sz, 0, -sz, cz, 0, 0, 0, 1);
    return rz * ry * rx;
}

bool solveQuadratic(float a, float b, float c, out float t0, out float t1) {
    float disc = b*b - 4.0*a*c;
    if (disc < 0.0) return false;
    float sqrtDisc = sqrt(disc);
    t0 = (-b - sqrtDisc) / (2.0*a);
    t1 = (-b + sqrtDisc) / (2.0*a);
    return true;
}

// --- PRIMITIVES ---

bool hitSphere(GPUObject obj, vec3 rayOrigin, vec3 rayDir, float tMin, float tMax, inout HitRecord rec) {
    vec3 center = obj.data1.xyz;
    float radius = obj.data1.w;
    vec3 oc = rayOrigin - center;
    float a = dot(rayDir, rayDir);
    float b = 2.0 * dot(oc, rayDir);
    float c = dot(oc, oc) - radius * radius;

    float t0, t1;
    if (!solveQuadratic(a, b, c, t0, t1)) return false;
    float root = t0;
    if (root <= tMin || root >= tMax) {
        root = t1;
        if (root <= tMin || root >= tMax) return false;
    }
    rec.t = root;
    rec.p = rayOrigin + rec.t * rayDir;
    vec3 outwardNormal = (rec.p - center) / radius;
    rec.frontFace = dot(rayDir, outwardNormal) < 0.0;
    rec.normal = rec.frontFace ? outwardNormal : -outwardNormal;

    rec.matIndex = int(obj.data2.x);  // ← FIXED: Read from .x, not .w
    return true;
}


bool hitPlane(GPUObject obj, vec3 rayOrigin, vec3 rayDir, float tMin, float tMax, inout HitRecord rec) {
    vec3 normal = normalize(obj.data1.xyz);
    float dist = obj.data1.w;
    float denom = dot(normal, rayDir);
    if (abs(denom) > 1e-6) {
        float t = -(dot(rayOrigin, normal) + dist) / denom;
        if (t > tMin && t < tMax) {
            rec.t = t;
            rec.p = rayOrigin + t * rayDir;
            rec.frontFace = denom < 0.0;
            rec.normal = rec.frontFace ? normal : -normal;

            // --- FIX: ASSIGN MATERIAL ---
            rec.matIndex = int(obj.data2.w);
            return true;
        }
    }
    return false;
}

bool hitLocalCylinder(vec3 ro, vec3 rd, vec3 scale, float tMin, float tMax, out float tOut, out vec3 nOut) {
    float r = scale.x;
    float h = scale.y;
    float halfH = h * 0.5;

    // Body
    float a = rd.x*rd.x + rd.z*rd.z;
    float b = 2.0 * (ro.x*rd.x + ro.z*rd.z);
    float c = ro.x*ro.x + ro.z*ro.z - r*r;

    float t0, t1;
    bool hitBody = solveQuadratic(a, b, c, t0, t1);

    float tClosest = tMax;
    vec3 nClosest = vec3(0,1,0);
    bool hit = false;

    if (hitBody) {
        float y0 = ro.y + t0 * rd.y;
        if (t0 > tMin && t0 < tClosest && y0 >= -halfH && y0 <= halfH) {
            tClosest = t0;
            nClosest = vec3(ro.x + t0*rd.x, 0.0, ro.z + t0*rd.z) / r;
            hit = true;
        }
        float y1 = ro.y + t1 * rd.y;
        if (t1 > tMin && t1 < tClosest && y1 >= -halfH && y1 <= halfH) {
            tClosest = t1;
            nClosest = vec3(ro.x + t1*rd.x, 0.0, ro.z + t1*rd.z) / r;
            hit = true;
        }
    }

    // Caps
    float tTop = (halfH - ro.y) / rd.y;
    vec3 pTop = ro + tTop * rd;
    if (tTop > tMin && tTop < tClosest && (pTop.x*pTop.x + pTop.z*pTop.z <= r*r)) {
        tClosest = tTop; nClosest = vec3(0,1,0); hit = true;
    }

    float tBot = (-halfH - ro.y) / rd.y;
    vec3 pBot = ro + tBot * rd;
    if (tBot > tMin && tBot < tClosest && (pBot.x*pBot.x + pBot.z*pBot.z <= r*r)) {
        tClosest = tBot; nClosest = vec3(0,-1,0); hit = true;
    }

    if (hit) { tOut = tClosest; nOut = nClosest; return true; }
    return false;
}

bool hitLocalCone(vec3 ro, vec3 rd, vec3 scale, float tMin, float tMax, out float tOut, out vec3 nOut) {
    float r = scale.x;
    float h = scale.y;
    float halfH = h * 0.5;

    float k = r / h;
    float k2 = k * k;

    vec3 ro_tip = ro; ro_tip.y -= halfH;

    float A = rd.x*rd.x + rd.z*rd.z - k2 * rd.y*rd.y;
    float B = 2.0 * (ro_tip.x*rd.x + ro_tip.z*rd.z - k2 * ro_tip.y * rd.y);
    float C = ro_tip.x*ro_tip.x + ro_tip.z*ro_tip.z - k2 * ro_tip.y * ro_tip.y;

    float t0, t1;
    bool hitBody = solveQuadratic(A, B, C, t0, t1);

    float tClosest = tMax;
    vec3 nClosest = vec3(0,1,0);
    bool hit = false;

    if (hitBody) {
        float y0 = ro.y + t0 * rd.y;
        if (t0 > tMin && t0 < tClosest && y0 >= -halfH && y0 <= halfH) {
            tClosest = t0;
            vec3 p = ro + t0 * rd;
            nClosest = normalize(vec3(p.x, -k2 * (p.y - halfH), p.z));
            hit = true;
        }
        float y1 = ro.y + t1 * rd.y;
        if (t1 > tMin && t1 < tClosest && y1 >= -halfH && y1 <= halfH) {
            tClosest = t1;
            vec3 p = ro + t1 * rd;
            nClosest = normalize(vec3(p.x, -k2 * (p.y - halfH), p.z));
            hit = true;
        }
    }

    // Base Cap
    float tBase = (-halfH - ro.y) / rd.y;
    vec3 pBase = ro + tBase * rd;
    if (tBase > tMin && tBase < tClosest && (pBase.x*pBase.x + pBase.z*pBase.z <= r*r)) {
        tClosest = tBase;
        nClosest = vec3(0, -1, 0);
        hit = true;
    }

    if (hit) { tOut = tClosest; nOut = nClosest; return true; }
    return false;
}

bool intersectConvexPlanes(vec3 ro, vec3 rd, vec3 scale, int type, float tMin, float tMax, out float tOut, out vec3 nOut) {
    float t0 = -1e6;
    float t1 = 1e6;

    vec3 n0 = vec3(0.0);
    vec3 n1 = vec3(0.0);

    if (type == TYPE_CUBE) {
        vec3 rad = scale;
        vec3 m = 1.0 / rd;
        vec3 n = m * ro;
        vec3 k = abs(m) * rad;
        vec3 t_1 = -n - k;
        vec3 t_2 = -n + k;

        float tN = max(max(t_1.x, t_1.y), t_1.z);
        float tF = min(min(t_2.x, t_2.y), t_2.z);

        if (tN > tF || tF < 0.0) return false;

        float t = tN;
        if (t <= tMin) t = tF;
        if (t <= tMin || t >= tMax) return false;

        tOut = t;
        vec3 p = ro + rd * tOut;
        vec3 s = sign(p);
        vec3 a = abs(p) / rad;

        if (a.x > a.y && a.x > a.z) nOut = vec3(s.x, 0, 0);
        else if (a.y > a.z)         nOut = vec3(0, s.y, 0);
        else                        nOut = vec3(0, 0, s.z);
        return true;
    }

    vec4 planes[20];
    int count = 0;
    float s = scale.x; // Radius / Scale

    if (type == TYPE_TETRAHEDRON) {
        // Distance to face = s / 3.0
        float d = s / 3.0;
        float k = 0.577350269; // 1/sqrt(3)
        planes[0] = vec4( k, k, k, d);
        planes[1] = vec4( k,-k,-k, d);
        planes[2] = vec4(-k, k,-k, d);
        planes[3] = vec4(-k,-k, k, d);
        count = 4;
    }
    else if (type == TYPE_PYRAMID) {
        // Square Pyramid (1x1 base, height 1)
        // Base is at y = -0.5*s, Apex at y = 0.5*s

        // Base plane (pointing down)
        planes[0] = vec4(0, -1, 0, s * 0.5);

        // Side planes
        // Normal slope = 2.0 (rise/run) -> normalized: (0.8944, 0.4472)
        float ny = 0.4472136;
        float nx = 0.8944271;
        // For a unit pyramid (base width 1, height 1), distance is 1/sqrt(5) ~ 0.4472 * (s/2)
        // Adjusted for scale 's' being full width/height
        float d = (s * 0.5) * nx; // ~ 0.447 * s

        planes[1] = vec4( nx, ny, 0, d);
        planes[2] = vec4(-nx, ny, 0, d);
        planes[3] = vec4( 0, ny, nx, d);
        planes[4] = vec4( 0, ny,-nx, d);
        count = 5;
    }
    else if (type == TYPE_PRISM) {
        float h = scale.y * 0.5;
        float r = scale.x * 0.5;

        // Top/Bottom caps
        planes[0] = vec4(0,  1, 0, h);
        planes[1] = vec4(0, -1, 0, h);

        // Sides (Equilateral triangle)
        float d = scale.x * 0.5;

        planes[2] = vec4(0, 0, 1, d); // Front face

        // Rotated faces (+- 120 deg)
        float kx = 0.866025; // sin(60)
        float kz = 0.5;      // cos(60)

        // Back-right: normal ( kx, 0, -kz)
        // Back-left:  normal (-kx, 0, -kz)
        planes[3] = vec4( kx, 0, -kz, d);
        planes[4] = vec4(-kx, 0, -kz, d);
        count = 5;
    }
    else if (type == TYPE_DODECAHEDRON) {

        float G = 1.61803398875; // Golden Ratio
        float k1 = 1.0 / sqrt(1.0 + G*G); // 0.52573111
        float k2 = G * k1;                // 0.85065080

        float d = s * 1.0;

        // 12 Faces
        planes[0] = vec4(0, k1, k2, d);  planes[1] = vec4(0, -k1, k2, d);
        planes[2] = vec4(0, k1,-k2, d);  planes[3] = vec4(0, -k1,-k2, d);
        planes[4] = vec4(k2, 0, k1, d);  planes[5] = vec4(k2, 0, -k1, d);
        planes[6] = vec4(-k2,0, k1, d);  planes[7] = vec4(-k2,0, -k1, d);
        planes[8] = vec4(k1, k2, 0, d);  planes[9] = vec4(k1, -k2, 0, d);
        planes[10]= vec4(-k1,k2, 0, d);  planes[11]= vec4(-k1,-k2, 0, d);
        count = 12;
    }
    else if (type == TYPE_ICOSAHEDRON) {
        // 20 faces.

        float G = 1.61803398875;
        // Normals (same as Dodecahedron vertices normalized)

        float d = s * 1.0;

        float n_a = 0.35682208;
        float n_b = 0.93417235;

        float k = 0.577350269;
        float m = 0.356822089;
        float n = 0.934172359;

        // 20 Faces
        planes[0] = vec4( k, k, k, d); planes[1] = vec4( k, k,-k, d);
        planes[2] = vec4( k,-k, k, d); planes[3] = vec4( k,-k,-k, d);
        planes[4] = vec4(-k, k, k, d); planes[5] = vec4(-k, k,-k, d);
        planes[6] = vec4(-k,-k, k, d); planes[7] = vec4(-k,-k,-k, d);

        planes[8] = vec4(0, m, n, d);  planes[9] = vec4(0, -m, n, d);
        planes[10]= vec4(0, m,-n, d);  planes[11]= vec4(0, -m,-n, d);
        planes[12]= vec4(n, 0, m, d);  planes[13]= vec4(n, 0, -m, d);
        planes[14]= vec4(-n,0, m, d);  planes[15]= vec4(-n,0, -m, d);
        planes[16]= vec4(m, n, 0, d);  planes[17]= vec4(m, -n, 0, d);
        planes[18]= vec4(-m,n, 0, d);  planes[19]= vec4(-m,-n, 0, d);
        count = 20;
    }

    // Slab Method Loop (Standard)
    for (int i = 0; i < count; i++) {
        vec4 p = planes[i];
        vec3 norm = p.xyz;
        float dist = p.w;

        float denom = dot(norm, rd);
        float num = dist - dot(norm, ro);

        if (abs(denom) < 1e-6) {
            if (num < 0.0) return false;
        } else {
            float t = num / denom;
            if (denom < 0.0) { if (t > t0) { t0 = t; n0 = norm; } }
            else { if (t < t1) { t1 = t; n1 = norm; } }
        }
    }

    if (t0 > t1) return false;

    float t = t0;
    // Inside logic: if entry is behind us, take exit.
    if (t <= tMin) t = t1;

    // Bounds check
    if (t <= tMin || t >= tMax) return false;

    tOut = t;
    nOut = (t == t0) ? n0 : n1; // Use correct normal depending on hit
    return true;
}

bool hitWorld(vec3 rayOrigin, vec3 rayDir, float tMin, float tMax, inout HitRecord rec) {
    bool hitAnything = false;
    float closestSoFar = tMax;

    for (int i = 0; i < objectCount; i++) {
        GPUObject obj = objects[i];
        int type = int(obj.data3.w);

        bool hit = false;
        float tHit = closestSoFar;
        vec3 nHit;

        if (type == TYPE_SPHERE) {
            if (hitSphere(obj, rayOrigin, rayDir, tMin, closestSoFar, rec)) {
                hitAnything = true;
                closestSoFar = rec.t;
                rec.objIndex = i;
            }
            continue;
        }

        if (type == TYPE_PLANE) {
            if (hitPlane(obj, rayOrigin, rayDir, tMin, closestSoFar, rec)) {
                hitAnything = true;
                closestSoFar = rec.t;
                rec.objIndex = i;
            }
            continue;
        }

        // Complex Shapes
        vec3 center = obj.data1.xyz;
        vec3 rot = obj.data2.xyz;
        vec3 scale = obj.data3.xyz;

        mat3 rotMat = buildRotationMatrix(rot);
        mat3 invRot = transpose(rotMat);

        vec3 roLocal = invRot * (rayOrigin - center);
        vec3 rdLocal = invRot * rayDir;

        bool localHit = false;
        if (type == TYPE_CYLINDER) localHit = hitLocalCylinder(roLocal, rdLocal, scale, tMin, closestSoFar, tHit, nHit);
        else if (type == TYPE_CONE) localHit = hitLocalCone(roLocal, rdLocal, scale, tMin, closestSoFar, tHit, nHit);
        else localHit = intersectConvexPlanes(roLocal, rdLocal, scale, type, tMin, closestSoFar, tHit, nHit);

        if (localHit) {
            hitAnything = true;
            closestSoFar = tHit;
            rec.t = tHit;
            rec.p = rayOrigin + tHit * rayDir;
            rec.normal = normalize(rotMat * nHit);
            rec.frontFace = dot(rayDir, rec.normal) < 0.0;
            if (!rec.frontFace) rec.normal = -rec.normal;
            rec.matIndex = int(obj.data2.w);
            rec.objIndex = i;
        }
    }
    return hitAnything;
}