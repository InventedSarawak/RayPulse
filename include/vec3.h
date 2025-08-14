#ifndef VEC3_H
#define VEC3_H

#include <stdio.h>

typedef struct {
    double e[3];
} vec3;

typedef vec3 point3;

vec3 vec3_create(double x, double y, double z);
vec3 vec3_negate(vec3 v);

double vec3_x(vec3 v);
double vec3_y(vec3 v);
double vec3_z(vec3 v);
double vec3_get(vec3 v, int index);
void vec3_set(vec3 *v, int index, double value);

void vec3_add_assign(vec3 *u, vec3 v);
void vec3_mul_assign(vec3 *v, double t);
void vec3_div_assign(vec3 *v, double t);

double vec3_length(vec3 v);
double vec3_length_squared(vec3 v);
vec3 vec3_add(vec3 u, vec3 v);
vec3 vec3_sub(vec3 u, vec3 v);
vec3 vec3_mul(vec3 u, vec3 v);
vec3 vec3_mul_scalar(vec3 v, double t);
vec3 vec3_div_scalar(vec3 v, double t);
double vec3_dot(vec3 u, vec3 v);
vec3 vec3_cross(vec3 u, vec3 v);
vec3 vec3_unit(vec3 v);

void vec3_print(vec3 v);

#endif
