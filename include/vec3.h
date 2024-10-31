#ifndef VEC3_H
#define VEC3_H

#include <math.h>
#include <stdlib.h>
#include <stdio.h>

typedef struct vec3 {
    float e[3];
} vec3;

vec3* vec3_init(int argc, char *argv[]) {
    if(argc == 0) {
        vec3 *vec = (vec3 *)malloc(sizeof(vec3));
        vec->e[0] = 0;
        vec->e[1] = 0;
        vec->e[2] = 0;
        return vec;
    } else if (argc == 3) {
        vec3 *vec = (vec3 *)malloc(sizeof(vec3));
        vec->e[0] = atof(argv[0]);
        vec->e[1] = atof(argv[1]);
        vec->e[2] = atof(argv[2]);
        return vec;
    } else fprintf(stderr, "Wrong number of arguments\n");
    return NULL;
}

float get_x(vec3 *vec) {
    return vec->e[0];
}

float get_y(vec3 *vec) {
    return vec->e[1];
}

float get_z(vec3 *vec) {
    return vec->e[2];
}

float vec3_get(vec3 *vec, int index) {
    if(index < 0 && index > 2) fprintf(stderr, "Index out of bounds\n");
    return vec->e[index];
}

vec3 vec3_negate(vec3 *vec) {
    vec->e[0] = -vec->e[0];
    vec->e[1] = -vec->e[1];
    vec->e[2] = -vec->e[2];
    return *vec;
}

// TODO: @InventedSarawak Complete the vec3.h library

void vec3_print(vec3 *vec) {
    printf("%f %f %f\n", get_x(vec), get_y(vec), get_z(vec));
}

void vec3_free(vec3 *vec) {
    free(vec);
    vec = NULL;
}

#endif