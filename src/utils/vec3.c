#include "vec3.h"
#include <math.h>

vec3 vec3_create(double x, double y, double z) {
    vec3 v = {{x, y, z}};
    return v;
}

vec3 vec3_negate(vec3 v) { return vec3_create(-v.e[0], -v.e[1], -v.e[2]); }

double vec3_x(vec3 v) { return v.e[0]; }
double vec3_y(vec3 v) { return v.e[1]; }
double vec3_z(vec3 v) { return v.e[2]; }

double vec3_get(vec3 v, int index) {
    if (index < 0 || index > 2)
        return 0.0;
    return v.e[index];
}

void vec3_set(vec3 *v, int index, double value) {
    if (index < 0 || index > 2)
        return;
    v->e[index] = value;
}

void vec3_add_assign(vec3 *u, vec3 v) {
    u->e[0] += v.e[0];
    u->e[1] += v.e[1];
    u->e[2] += v.e[2];
}

void vec3_mul_assign(vec3 *v, double t) {
    v->e[0] *= t;
    v->e[1] *= t;
    v->e[2] *= t;
}

void vec3_div_assign(vec3 *v, double t) { vec3_mul_assign(v, 1.0 / t); }

double vec3_length(vec3 v) { return sqrt(vec3_length_squared(v)); }

double vec3_length_squared(vec3 v) { return v.e[0] * v.e[0] + v.e[1] * v.e[1] + v.e[2] * v.e[2]; }

vec3 vec3_add(vec3 u, vec3 v) {
    return vec3_create(u.e[0] + v.e[0], u.e[1] + v.e[1], u.e[2] + v.e[2]);
}

vec3 vec3_sub(vec3 u, vec3 v) {
    return vec3_create(u.e[0] - v.e[0], u.e[1] - v.e[1], u.e[2] - v.e[2]);
}

vec3 vec3_mul(vec3 u, vec3 v) {
    return vec3_create(u.e[0] * v.e[0], u.e[1] * v.e[1], u.e[2] * v.e[2]);
}

vec3 vec3_mul_scalar(vec3 v, double t) { return vec3_create(v.e[0] * t, v.e[1] * t, v.e[2] * t); }

vec3 vec3_div_scalar(vec3 v, double t) { return vec3_mul_scalar(v, 1.0 / t); }

double vec3_dot(vec3 u, vec3 v) { return u.e[0] * v.e[0] + u.e[1] * v.e[1] + u.e[2] * v.e[2]; }

vec3 vec3_cross(vec3 u, vec3 v) {
    return vec3_create(u.e[1] * v.e[2] - u.e[2] * v.e[1], u.e[2] * v.e[0] - u.e[0] * v.e[2],
                       u.e[0] * v.e[1] - u.e[1] * v.e[0]);
}

vec3 vec3_unit(vec3 v) { return vec3_div_scalar(v, vec3_length(v)); }

void vec3_print(vec3 v) { printf("%f %f %f\n", v.e[0], v.e[1], v.e[2]); }
